function [pBatt_kW, SoCvec] = batteryModel(resNoBatt_kW, dtHours, capacity_kWh, pMax_kW, effRoundTrip)
% batteryModel.m
% -------------------------------------------------------------------------
% Stationärer PV-Speicher:
%   - Eingabe: resNoBatt_kW (kW), dtHours, capacity_kWh, pMax_kW, effRoundTrip
%   - Ausgabe:
%       pBatt_kW: positive Werte: Entladung, negative Werte: Laden.
%       SoCvec: SoC-Werte (zwischen 0 und 1) pro Zeitschritt.
% -------------------------------------------------------------------------

nSteps = length(resNoBatt_kW);
SoCvec = zeros(nSteps,1);
SoC = 0;  % Startwert

effC = sqrt(effRoundTrip);
effD = sqrt(effRoundTrip);

pBatt_kW = zeros(nSteps,1);

for i = 1:nSteps
    deltaP_kW = resNoBatt_kW(i);
    if deltaP_kW > 0
        pDis_kW = min(pMax_kW, deltaP_kW);
        Eneeded_kWh = pDis_kW * dtHours;
        Eavail_kWh = SoC * capacity_kWh;
        Eent_kWh = min(Eneeded_kWh / effD, Eavail_kWh);
        SoC = SoC - (Eent_kWh / capacity_kWh);
        pDisActual_kW = (Eent_kWh * effD) / dtHours;
        pBatt_kW(i) = pDisActual_kW;
    else
        pChg_kW = min(pMax_kW, -deltaP_kW);
        if pChg_kW < 0, pChg_kW = 0; end
        Eexcess_kWh = pChg_kW * dtHours * effC;
        Efree_kWh = (1 - SoC) * capacity_kWh;
        Estore_kWh = min(Eexcess_kWh, Efree_kWh);
        SoC = SoC + (Estore_kWh / capacity_kWh);
        pUsed_kW = (Estore_kWh / effC) / dtHours;
        pBatt_kW(i) = -pUsed_kW;
    end
    if SoC < 0, SoC = 0; end
    if SoC > 1, SoC = 1; end
    SoCvec(i) = SoC;
end
end
