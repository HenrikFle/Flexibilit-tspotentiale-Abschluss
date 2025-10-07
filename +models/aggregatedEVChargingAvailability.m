function availability = aggregatedEVChargingAvailability(t)
% aggregatedEVChargingAvailability.m
% -------------------------------------------------------------------------
% Diese Funktion gibt den aggregierten Verfügbarkeitsfaktor (0 bis 1) 
% für das Laden/V2G der EV-Flotte zurück, basierend auf gruppenspezifischen
% Lade-/Verfügbarkeitszeiten.
%
% Fahrzeuggruppen:
%   Gruppe A – Early Home-based Commuter EVs:
%       Verfügbarkeit: 1, wenn t < 6 oder t ≥ 15.
%
%   Gruppe B – Workplace-based EVs:
%       Verfügbarkeit: 1, wenn t zwischen 08:00 und 17:00 Uhr liegt.
%
%   Gruppe C – Home-based Commuter EVs 2:
%       Verfügbarkeit: 1, wenn t < 9 oder t ≥ 18.
%
%   Gruppe D – Dual-Access EVs:
%       Verfügbarkeit: 1, wenn t nicht in den Intervallen [07,10) und [15,18) liegt.
%
% Die gruppenspezifischen Verfügbarkeitsfaktoren werden anteilig gewichtet.
% -------------------------------------------------------------------------

dt = 0.25;
t_base = (0:dt:24-dt)';

availA = double((t_base < 6) | (t_base >= 15));
availB = double((t_base >= 8) & (t_base < 17));
availC = double((t_base < 9) | (t_base >= 18));
availD = double(~(((t_base >= 7) & (t_base < 10)) | ((t_base >= 15) & (t_base < 18))));

pA = 0.3; pB = 0.25; pC = 0.3; pD = 0.15;
availability_base = pA*availA + pB*availB + pC*availC + pD*availD;
availability = interp1(t_base, availability_base, t, 'linear', 'extrap');
