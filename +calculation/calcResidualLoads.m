% File: +calculation/calcResidualLoads.m

function residualResults = calcResidualLoads( ...
    normalDataSel, pvDataSel, dtHours, ...
    capacityBatt_kWh, pMaxBatt_kW, effRoundTrip, ...
    useEV, capacityEV_kWh, pMaxEV_kW, numEV, ...
    flexWindowDays, flexStdMultiplier, hpCount, flexBoundsOverride)
% calcResidualLoads.m  – inklusive DHW-WP
% ------------------------------------------------------------
%   Erzeugt Residuallasten & Flex-Energieblöcke.
%   HEIZPERIODEN-ERGÄNZUNG:
%       Heizungs-WP zählt nur vom 1. Okt bis 30. Apr.
% ------------------------------------------------------------

if nargin < 14 || isempty(flexBoundsOverride)
    flexBoundsOverride = struct();
end

%% 0) Basis-Daten ----------------------------------------------------------
merged = outerjoin(normalDataSel, pvDataSel, ...
    'Keys','Timestamp','MergeKeys',true,'Type','full');
merged.Power_normalDataSel(isnan(merged.Power_normalDataSel)) = 0;
merged.Power_pvDataSel   (isnan(merged.Power_pvDataSel))     = 0;

baseLoad_kW = merged.Power_normalDataSel;
pv_kW       = merged.Power_pvDataSel;
nSteps      = length(baseLoad_kW);

%% 1) WP-Simulation: Heizung (statisch & flexibel) -------------------------
ts0         = merged.Timestamp(1);
startDatePy = py.datetime.datetime( ...
    int64(year(ts0)), int64(month(ts0)), int64(day(ts0)), ...
    int64(hour(ts0)), int64(minute(ts0)));

simStaticHeat = py.hisim_matlab_bridge.HiSimHeatPumpSim( ...
                    startDatePy, int64(dtHours*3600), int64(nSteps));

wpStatic_kW = zeros(nSteps,1);

% Preallocate arrays für Raumtemperaturen (statisch und dynamisch WP)
T_room_stat = nan(nSteps,1);

%% 1a) DHW-Simulation ------------------------------------------------------
simStaticDHW = py.hisim_matlab_bridge.HiSimDHWOnlySim( ...
                    startDatePy, int64(dtHours*3600), int64(nSteps));

dhwStatic_kW = zeros(nSteps,1);

%% 1b) Haupt-Zeitschleife (statisch) --------------------------------------
for i = 1:nSteps
    ts_now = merged.Timestamp(i);

    % ---------- Heizungs-WP (statisch) -----------------------------------
    m = month(ts_now); d = day(ts_now);
    inHeatingSeason = ...
         (m > 10) || (m < 4)  || (m == 10) || (m == 4 && d <= 30);

    % summer cooling: keep room temperature below 24 °C
    Tcool = 24;

    if inHeatingSeason
        outS = simStaticHeat.step(int64(20), int64(Tcool));
    else
        outS = simStaticHeat.step(int64(15), int64(Tcool), int64(23));
    end
    wpStatic_kW(i) = double(outS{1});
    T_room_stat(i)  = double(outS{2});

    % ---------- DHW-WP (statisch) ----------------------------------------
    outDS = simStaticDHW.step_dhw(int64(50));
    dhwStatic_kW(i) = double(outDS{1});
end

%% 1c) Aggregation auf Quartier-Ebene (statisch) --------------------------
wpAgg_kW  = models.aggregatedWPModel(wpStatic_kW, hpCount, dtHours);

% Skalierung der Warmwasser-Wärmepumpen analog zu den Heizungs-WPs. Die
% Anzahl der DHW‑WPs entspricht dabei hpCount und ihre Einzelprofile
% werden ebenfalls mit normalverteilten Zeitversätzen verschoben.
dhwAgg_kW = models.aggregatedWPModel(dhwStatic_kW, hpCount, dtHours);

%% 2) Residuallast ohne Speicher ------------------------------------------
resNoStorage_kW = (baseLoad_kW + wpAgg_kW + dhwAgg_kW) - pv_kW;

%% 2a) Statische Flex-Grenzen auf Wochenmittelbasis -----------------------
useOverride = isstruct(flexBoundsOverride) && ...
              isfield(flexBoundsOverride, 'lower') && ...
              isfield(flexBoundsOverride, 'upper');

if useOverride
    flexLowerBound = flexBoundsOverride.lower(:);
    flexUpperBound = flexBoundsOverride.upper(:);

    if numel(flexLowerBound) ~= nSteps || numel(flexUpperBound) ~= nSteps
        error('calcResidualLoads:BoundsLengthMismatch', ...
              'Override-Grenzen müssen Länge %d haben.', nSteps);
    end

    if isfield(flexBoundsOverride, 'baseline')
        baseline = flexBoundsOverride.baseline(:);
        if numel(baseline) ~= nSteps
            error('calcResidualLoads:BaselineLengthMismatch', ...
                  'Override-Baseline muss Länge %d haben.', nSteps);
        end
    else
        baseline = (flexUpperBound + flexLowerBound) / 2;
    end

    if isfield(flexBoundsOverride, 'spread')
        spread = abs(flexBoundsOverride.spread(:));
        if numel(spread) ~= nSteps
            error('calcResidualLoads:SpreadLengthMismatch', ...
                  'Override-Spread muss Länge %d haben.', nSteps);
        end
    else
        spread = abs(flexUpperBound - baseline);
    end
else
    weeklyMean = mean(resNoStorage_kW, 'omitnan');
    if isnan(weeklyMean)
        weeklyMean = 0;
    end

    flexStdMultiplier = max(flexStdMultiplier, 0);
    if flexStdMultiplier == 0
        flexStdMultiplier = 0.20;  % Default: ±20 % falls nicht gesetzt
    end

    baseline = weeklyMean * ones(nSteps, 1);
    spread   = abs(weeklyMean) * flexStdMultiplier * ones(nSteps, 1);

    flexLowerBound = baseline - spread;
    flexUpperBound = baseline + spread;
end

maskLower = isnan(flexLowerBound);
maskUpper = isnan(flexUpperBound);
flexLowerBound(maskLower) = resNoStorage_kW(maskLower);
flexUpperBound(maskUpper) = resNoStorage_kW(maskUpper);

%% 2b) WP-Simulation (flexibel) -------------------------------------------
simFlexHeat = py.hisim_matlab_bridge.HiSimHeatPumpSim( ...
                    startDatePy, int64(dtHours*3600), int64(nSteps));
simFlexDHW  = py.hisim_matlab_bridge.HiSimDHWOnlySim( ...
                    startDatePy, int64(dtHours*3600), int64(nSteps));

wpFlex_kW  = zeros(nSteps,1);
dhwFlex_kW = zeros(nSteps,1);
T_room_dyn = nan(nSteps,1);

for i = 1:nSteps
    ts_now = merged.Timestamp(i);

    m = month(ts_now); d = day(ts_now);
    inHeatingSeason = ...
         (m > 10) || (m < 4)  || (m == 10) || (m == 4 && d <= 30);
    Tcool = 24;

    residual_now = baseLoad_kW(i) + wpStatic_kW(i) - pv_kW(i);
    lower = flexLowerBound(i);
    upper = flexUpperBound(i);
    baseVal = baseline(i);

    if isnan(lower)
        lower = baseVal;
    end
    if isnan(upper)
        upper = baseVal;
    end
    if isnan(lower)
        lower = resNoStorage_kW(i);
    end
    if isnan(upper)
        upper = resNoStorage_kW(i);
    end

    if inHeatingSeason
        if residual_now < lower
            Tset = 22;          % „Vorziehen“
        elseif residual_now > upper
            Tset = 19;          % „Zurückhalten“
        else
            Tset = 20;
        end
        outF = simFlexHeat.step(int64(Tset), int64(25));
    else
        Tset = 15;              % no heating in summer
        if residual_now < lower
            outF = simFlexHeat.step(int64(Tset), int64(Tcool), int64(21));
        elseif residual_now > upper
            outF = simFlexHeat.step(int64(Tset), int64(Tcool), int64(24));
        else
            outF = simFlexHeat.step(int64(Tset), int64(Tcool), int64(23));
        end
    end
    wpFlex_kW(i) = double(outF{1});
    T_room_dyn(i)   = double(outF{2});

    if residual_now < lower
        TsetDHW = 70;
    elseif residual_now > upper
        TsetDHW = 45;
    else
        TsetDHW = 50;
    end
    outDF = simFlexDHW.step_dhw(int64(TsetDHW));
    dhwFlex_kW(i) = double(outDF{1});
end

%% 2c) Aggregation auf Quartier-Ebene (flexibel) --------------------------
wpFlexAgg_kW  = models.aggregatedWPModel(wpFlex_kW,   hpCount, dtHours);
dhwFlexAgg_kW = models.aggregatedWPModel(dhwFlex_kW, hpCount, dtHours);

%% 3) Batterie -------------------------------------------------------------
[pBatt_kW, SoC_Batt] = models.batteryModel( ...
    resNoStorage_kW, dtHours, capacityBatt_kWh, pMaxBatt_kW, effRoundTrip, ...
    flexLowerBound, flexUpperBound);
resWithBatt_kW = resNoStorage_kW - pBatt_kW;

%% 4) EV-Modell -----------------------------------------------------------
if useEV
    [pEV_kW, SoC_EV, ~, SoC_groups] = models.aggregatedEVModel( ...
        resNoStorage_kW, dtHours, numEV, pMaxEV_kW, capacityEV_kWh, ...
        flexLowerBound, flexUpperBound);
else
    pEV_kW       = zeros(nSteps,1);
    SoC_EV       = zeros(nSteps,1);
    SoC_groups.A = zeros(nSteps,1);
    SoC_groups.B = SoC_groups.A;
    SoC_groups.C = SoC_groups.A;
    SoC_groups.D = SoC_groups.A;
end

%% 4a) Basalladen / Flex-Signal trennen -----------------------------------
deltaP  = resNoStorage_kW;

minSOC  = 0.40;

withinBand = (deltaP >= flexLowerBound) & (deltaP <= flexUpperBound);
isBasal = withinBand & pEV_kW<0;
isSurplus = deltaP <= flexLowerBound;
isEmerg = (SoC_EV<minSOC) & (pEV_kW<0) & ~isSurplus;
maskCharge   = isBasal | isEmerg;



pEV_charge            = zeros(nSteps,1);

pEV_charge(maskCharge)= -pEV_kW(maskCharge);

pEV_flex              = pEV_kW;

pEV_flex(maskCharge)  = 0;


%% 5) Weitere Residuallasten ----------------------------------------------
resWithEV_kW   = resNoStorage_kW - pEV_kW;
resWithBoth_kW = resNoStorage_kW - pBatt_kW - pEV_kW;

%% 6) Flex-Energieblöcke (Ø kWh / Tag) ------------------------------------
dBatt = resNoStorage_kW - resWithBatt_kW;
dWP_total  = (wpFlexAgg_kW   - wpAgg_kW) + (dhwFlexAgg_kW  - dhwAgg_kW);
dEV   = pEV_flex;

dt_kWh = dtHours;
Epos = @(x) sum(max(0,x))*dt_kWh/7;
Eneg = @(x) sum(min(0,x))*dt_kWh/7;

flexTable.names    = {'Batterie','WP','EV'};
flexTable.Epos_kWh = [Epos(dBatt); Epos(dWP_total); Epos(dEV)];
flexTable.Eneg_kWh = [Eneg(dBatt); Eneg(dWP_total); Eneg(dEV)];

%% 7) Ergebnisse zurück ---------------------------------------------------
residualResults.Timestamp           = merged.Timestamp;

residualResults.Residual_NoStorage  = resNoStorage_kW;
residualResults.Residual_WithBatt   = resWithBatt_kW;
residualResults.Residual_WithEV     = resWithEV_kW;
residualResults.Residual_WithBoth   = resWithBoth_kW;

residualResults.baseLoad_kW         = baseLoad_kW;
residualResults.wpAgg_kW            = wpAgg_kW;
residualResults.wpFlexAgg_kW        = wpFlexAgg_kW;
residualResults.dhwAgg_kW           = dhwAgg_kW;
residualResults.dhwFlexAgg_kW        = dhwFlexAgg_kW;

residualResults.EV_charge_kW        = pEV_charge;
residualResults.pEV_total           = pEV_kW;
residualResults.pEV_flex            = pEV_flex;

residualResults.SoC_Batt            = SoC_Batt;
residualResults.SoC_EV              = SoC_EV;
residualResults.SoC_groups          = SoC_groups;

residualResults.flexEnergyTable     = flexTable;
residualResults.flexBaseline_kW     = baseline;
residualResults.flexSpread_kW       = spread;
residualResults.flexLowerBound_kW   = flexLowerBound;
residualResults.flexUpperBound_kW   = flexUpperBound;

% Zusatzfelder für Energieblock-Plot
residualResults.pBatt_kW            = pBatt_kW;
residualResults.pMaxBatt_kW         = pMaxBatt_kW;
residualResults.dtHours             = dtHours;
residualResults.pMaxEV_kW           = pMaxEV_kW;
residualResults.numEV               = numEV;

% NEU: Raumtemperaturen hinzufügen
residualResults.T_room_stat         = T_room_stat;
residualResults.T_room_dyn          = T_room_dyn;

end