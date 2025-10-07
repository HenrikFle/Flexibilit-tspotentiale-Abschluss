function [pBatt_kW, SoCvec] = batteryModel(resNoBatt_kW, dtHours, capacity_kWh, pMax_kW, effRoundTrip, varargin)
% batteryModel.m
% -------------------------------------------------------------------------
% Stationärer PV-Speicher:
%   - Eingabe: resNoBatt_kW (kW), dtHours, capacity_kWh, pMax_kW, effRoundTrip
%              [optional] flexLowerBoundVec, flexUpperBoundVec
%   - Ausgabe:
%       pBatt_kW: positive Werte: Entladung, negative Werte: Laden.
%       SoCvec: SoC-Werte (zwischen 0 und 1) pro Zeitschritt.
% -------------------------------------------------------------------------

flexLowerBoundVec = [];
flexUpperBoundVec = [];

if ~isempty(varargin)
    flexLowerBoundVec = varargin{1};
end
if length(varargin) >= 2
    flexUpperBoundVec = varargin{2};
end

nSteps = length(resNoBatt_kW);

if isempty(flexLowerBoundVec) || isempty(flexUpperBoundVec)
    % Rückfall: klassische Regel „über 0 entladen, unter 0 laden“
    flexLowerBoundVec = zeros(nSteps,1);
    flexUpperBoundVec = zeros(nSteps,1);
else
    flexLowerBoundVec = flexLowerBoundVec(:);
    flexUpperBoundVec = flexUpperBoundVec(:);
    if length(flexLowerBoundVec) ~= nSteps || length(flexUpperBoundVec) ~= nSteps
        error('batteryModel:BoundsLengthMismatch', ...
            'flexLowerBoundVec/flexUpperBoundVec müssen Länge %d haben.', nSteps);
    end
end

SoCvec = zeros(nSteps,1);
SoC = 0;  % Startwert

effC = sqrt(effRoundTrip);
effD = sqrt(effRoundTrip);

pBatt_kW = zeros(nSteps,1);

if capacity_kWh <= 0 || pMax_kW <= 0
    return;
end

for i = 1:nSteps
    deltaP_kW = resNoBatt_kW(i);
    lower = flexLowerBoundVec(i);
    upper = flexUpperBoundVec(i);

    if isnan(lower)
        lower = deltaP_kW;
    end
    if isnan(upper)
        upper = deltaP_kW;
    end

    if deltaP_kW > upper
        % Entladen, um die Residuallast in Richtung Obergrenze zu drücken
        desired_kW = min(deltaP_kW - upper, pMax_kW);
        if desired_kW > 0
            Eneeded_kWh = desired_kW * dtHours;
            Eavail_kWh  = SoC * capacity_kWh;
            Eent_kWh    = min(Eneeded_kWh / effD, Eavail_kWh);
            SoC         = SoC - (Eent_kWh / capacity_kWh);
            pBatt_kW(i) = (Eent_kWh * effD) / dtHours;
        end
    elseif deltaP_kW < lower
        % Laden, um die Residuallast zur Untergrenze anzuheben
        desired_kW = min(lower - deltaP_kW, pMax_kW);
        if desired_kW > 0
            Eexcess_kWh = desired_kW * dtHours * effC;
            Efree_kWh   = (1 - SoC) * capacity_kWh;
            Estore_kWh  = min(Eexcess_kWh, Efree_kWh);
            SoC         = SoC + (Estore_kWh / capacity_kWh);
            pBatt_kW(i) = -(Estore_kWh / effC) / dtHours;
        end
    end

    if SoC < 0, SoC = 0; end
    if SoC > 1, SoC = 1; end
    SoCvec(i) = SoC;
end
end