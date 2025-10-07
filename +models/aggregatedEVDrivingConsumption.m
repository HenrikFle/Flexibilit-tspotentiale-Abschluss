function drivingProfile = aggregatedEVDrivingConsumption(t, numEV)
% aggregatedEVDrivingConsumption.m
% -------------------------------------------------------------------------
% Diese Funktion liefert das aggregierte Fahrverbrauchsprofil (in kW)
% einer EV-Flotte basierend auf gruppenspezifischen Fahrzeiten.
%
% Annahmen:
% - Der durchschnittliche jährliche Fahrverbrauch beträgt 2250 kWh pro EV,
%   was ca. 6,16 kWh pro Tag entspricht.
% - Der aggregierte tägliche Verbrauch wird durch Multiplikation mit der
%   Anzahl der EVs (numEV) berechnet.
%
% Falls kein Zeitvektor t übergeben wird, wird ein Standard-Zeitvektor in
% 15-Minuten-Schritten (0:0.25:24) verwendet.
% -------------------------------------------------------------------------

dt = 0.25;
if nargin < 1 || isempty(t)
    t = (0:dt:24-dt)';
end

if nargin < 2 || isempty(numEV)
    error('Parameter numEV (Anzahl der EVs) muss übergeben werden.');
end

t_base = (0:dt:24-dt)';

% Aggregierter täglicher Verbrauch (kWh/Tag) für alle EVs:
dailyEVConsumption = (2250 / 365) * numEV;

% Gruppenanteile
pA = 0.3; pB = 0.25; pC = 0.3; pD = 0.15;
consA = pA * dailyEVConsumption;
consB = pB * dailyEVConsumption;
consC = pC * dailyEVConsumption;
consD = pD * dailyEVConsumption;

% Definition der Fahrphasen (1 = fahren) in 15-Minuten-Schritten
driveA = double((t_base >= 6) & (t_base < 15));
driveB = 1 - double((t_base >= 8) & (t_base < 17));
driveC = double((t_base >= 9) & (t_base < 18));
driveD = double(((t_base >= 7) & (t_base < 10)) | ((t_base >= 15) & (t_base < 18)));

% Gesamtfahrzeit (in Stunden) pro Gruppe
driveTimeA = sum(driveA) * dt;
driveTimeB = sum(driveB) * dt;
driveTimeC = sum(driveC) * dt;
driveTimeD = sum(driveD) * dt;

% Durchschnittliche Verbrauchsrate (in kW) während der Fahrphase
rateA = consA / driveTimeA;
rateB = consB / driveTimeB;
rateC = consC / driveTimeC;
rateD = consD / driveTimeD;

% Fahrverbrauchsprofile pro Gruppe (kW)
profileA = driveA * rateA;
profileB = driveB * rateB;
profileC = driveC * rateC;
profileD = driveD * rateD;

% Aggregiertes Fahrverbrauchsprofil
profileBase = profileA + profileB + profileC + profileD;
drivingProfile = interp1(t_base, profileBase, t, 'linear', 'extrap');

end
