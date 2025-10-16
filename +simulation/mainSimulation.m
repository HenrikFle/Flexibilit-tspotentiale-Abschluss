%Datei: +simulation/mainSimulation.m
% -------------------------------------------------------------------------
% mainSimulation   Top-Level-Skript
% -------------------------------------------------------------------------
% Dieser Einstiegspunkt steuert die komplette Quartierssimulation:
%   1) Aufräumen evtl. offener Python-Sessions.
%   2) Initialisieren einer HiSim-Python-Umgebung (In-Process-Modus).
%   3) Hinzufügen des Projekt-Roots zum Python-Suchpfad, damit die Bridge
%      sowie weitere Python-Module gefunden werden.
%   4) Interne Test-Import-Kontrolle (fehlert früh, falls Path falsch).
%   5) Benutzerführung über GUI-Menüs:
%        • Szenario wählen (Aktuell/2030/2050).
%        • Quartier wählen (Stadtquartier, Innenstädtisch, Ländlich).
%        • Zeitraum (Winter/Sommer/Übergangszeit) wählen.
%   6) Aufruf der Kernrechenfunktion calcResidualLoads und Visualisierung
%   6) Szenarioparameter über config.getScenarioParams laden.
%   7) Aufruf der Kernrechenfunktion calcResidualLoads und Visualisierung
%      der Ergebnisse via plotQuartierResults.
% -------------------------------------------------------------------------
function mainSimulation
    %% 0) Alte Python-Session bereinigen -----------------------------------
    clear classes      % entlädt ggf. noch in MATLAB eingebettete Py-Klassen
    % Hinweis: pyenv("ExecutionMode","InProcess") erlaubt kein terminate()

    %% 1) Python-Interpreter-Pfad (HiSim-Venv) -----------------------------
    %pythonExe   = 'C:\Users\JOCHE\HiSim\hisimvenv\Scripts\python.exe';
    %projectRoot = 'C:\Users\JOCHE\HiSim';   % Root-Ordner für HiSim-Quellen


    pythonExe   = "C:\Users\JOCHE\Desktop\WPSimulation2\HiSim\hisimvenv\Scripts\python.exe";
    projectRoot = "C:\Users\JOCHE\Desktop\WPSimulation2\HiSim";   % Root-Ordner für HiSim-Quellen


    %% 2) Python-Umgebung initialisieren ----------------------------------
    % In-Process verhindert den Overhead eines separaten Python-Prozesses,
    % setzt aber voraus, dass keine zweite Session parallel aktiv ist.
    pyenv('Version', pythonExe, 'ExecutionMode', 'InProcess');

    %% 3) Projekt-Root in sys.path einfügen (falls noch nicht vorhanden) ---
    projectRootPy = py.str(projectRoot);
    if count(py.sys.path, projectRootPy) == 0
        insert(py.sys.path, int32(0), projectRootPy); % ganz vorne eintragen
    end

    %% 4) Smoke-Test: Python-Modul importieren -----------------------------
    % Abbruch an dieser Stelle, falls die Bridge nicht gefunden wird.
    py.importlib.import_module('hisim_matlab_bridge');

    %% 5) Hauptschleife – ermöglicht Mehrfachsimulationen ------------------
    while true
        close all;           % schließt alte Figuren vor neuem Run
        clc;                 % Command Window leeren

        %% 5.1) CSV-Daten einlesen & Vorverarbeiten -----------------------
        [dataEFH, dataMFH_k, dataMFH_m, dataMFH_g, pvDataRaw, ...
          winterMonths, sommerMonths, uebergangszeitMonths] = ...
            data_import.readAndPreprocessData();

        %% 5.2) Szenario wählen -------------------------------------------
        scenarioChoice = menu('Wähle Szenario:', ...
                              'Aktuelles Szenario', ...
                              'Szenario 2030', ...
                              'Szenario 2050', ...
                              'Exit');
        if scenarioChoice == 0 || scenarioChoice == 4
            break;   % Abbruch über X/Exit
        end

        %% 5.3) Quartier via Menü wählen ---------------------------------
        quartierChoice = menu('Wähle Quartier:', ...
                              'Quartier 1: Stadtquartier (Verl)', ...
                              'Quartier 2: Innenstädtisches Quartier (Berlin-Mitte)', ...
                              'Quartier 3: Ländliches Quartier (Neuhof (Sundhagen))', ...
                              'Exit');
        if quartierChoice == 0 || quartierChoice == 4   % Abbruch über X/Exit
            break;
        end

        %% 5.3) Parameter aus Konfiguration ------------------------------
        params = config.getScenarioParams(scenarioChoice, quartierChoice);
        roundTripEff     = params.roundTripEff;
        useEV            = params.useEV;
        numEV            = params.numEV;
        capacityEV_kWh   = params.capacityEV_kWh;
        pMaxEV_kW        = params.pMaxEV_kW;
        capacityBatt_kWh = params.capacityBatt_kWh;
        pMaxBatt_kW      = params.pMaxBatt_kW;
        hpCount          = params.hpCount;
        pvScaleMWp       = params.pvScaleMWp;
        buildingWeights  = params.buildingWeights;

        %% 5.5) Quartiersbezogene Datenaufbereitung ----------------------
        switch quartierChoice
            case {1,2,3}   % Aktuell alle Quartiere wie Quartier 1
                % ---- Gebäude-Lasten zu einer Tabelle mergen -------------
                merged1 = outerjoin(dataEFH,   dataMFH_k, 'Keys','Timestamp', ...
                                    'MergeKeys',true,'Type','full');
                merged2 = outerjoin(merged1,   dataMFH_m, 'Keys','Timestamp', ...
                                    'MergeKeys',true,'Type','full');
                merged3 = outerjoin(merged2,   dataMFH_g, 'Keys','Timestamp', ...
                                    'MergeKeys',true,'Type','full');

                % Sicherstellen, dass fehlende Spalten mit Nullen existieren
                vars = {'Power','Power_dataMFH_k','Power_dataMFH_m','Power_dataMFH_g'};
                for v = vars
                    if ~ismember(v{1}, merged3.Properties.VariableNames)
                        merged3.(v{1}) = zeros(height(merged3),1);      % Spalte anlegen
                    else
                        idx = isnan(merged3.(v{1}));
                        merged3.(v{1})(idx) = 0;                         % NaN → 0
                    end
                end

                % Gebäude-Gewichtungen (Wärmebedarf pro Gebäudeart)
                sumW = merged3.Power*buildingWeights.EFH + ...
                       merged3.Power_dataMFH_k*buildingWeights.MFH_k + ...
                       merged3.Power_dataMFH_m*buildingWeights.MFH_m + ...
                       merged3.Power_dataMFH_g*buildingWeights.MFH_g;
                normalData = table(merged3.Timestamp, sumW*1e-3, ...
                                     'VariableNames', {'Timestamp','Power'});

                pvData  = pvDataRaw;   % PV-Profil unverändert übernehmen
                hpCount = 920;         % Anzahl Wärmepumpen im Quartier
                hpCount = params.hpCount;  % Anzahl Wärmepumpen

            otherwise
                break;   % sollte nicht auftreten
        end

        %% 5.5) Zeitraum-Menü -------------------------------------------
        %% 5.6) Zeitraum-Menü -------------------------------------------
        while true
            choice = menu('Zeitraum (KW)?', ...
                          'Winter (KW2)', 'Sommer (KW32)', ...       %%%%26
                          'Übergangszeit (KW36)', 'Zurück');
            if choice == 0 || choice == 4
                break;          % zurück ins Hauptmenü
            end
            switch choice
                case 1, zeitraumName = 'Winter';        months = winterMonths;        cw = 2;
                case 2, zeitraumName = 'Sommer';        months = sommerMonths;        cw = 32; %26
                case 3, zeitraumName = 'Übergangszeit'; months = uebergangszeitMonths;cw = 36;
            end

            dt = 0.25;  % Zeitraster in Stunden (15-min)

            %% --- Datenauswahl nach Monat + Kalenderwoche ---------------
            ND = normalData(ismember(month(normalData.Timestamp), months), :);
            if ~isempty(ND), ND.KW = week(ND.Timestamp); end
            normalDataSel = ND(ND.KW == cw, :);

            PD = pvData(ismember(month(pvData.Timestamp), months), :);
            if ~isempty(PD), PD.KW = week(PD.Timestamp); end
            pvDataSelRaw = PD(PD.KW == cw, :);
            if ~isempty(pvDataSelRaw)
                pvDataSel       = pvDataSelRaw;
                pvDataSel.Power = pvDataSel.Power * pvScaleMWp
            else
                pvDataSel = pvDataSelRaw;  % leer, gleiche Struktur
            end

            %% --- Plausibilitätscheck ----------------------------------
            if isempty(normalDataSel) && isempty(pvDataSel)
                fprintf('Keine Daten für %s / KW %d vorhanden.\n', ...
                        zeitraumName, cw);
                continue;  % zurück zum Zeitraum-Menü
            end

            %% --- Grenzwert für Basalladen (Mittelwert Vortag) ----------
                     if ~isempty(normalDataSel)
                nPerDay = round(24/dt);
                nSteps  = height(normalDataSel);
                prevDayMean = zeros(nSteps,1);
                for d = 1:ceil(nSteps/nPerDay)
                    idx_curr = (d-1)*nPerDay + (1:nPerDay);
                    idx_curr = idx_curr(idx_curr <= nSteps);
                    if d == 1
                        idx_prev = idx_curr;
                    else
                        idx_prev = (d-2)*nPerDay + (1:nPerDay);
                    end
                    meanVal = mean(normalDataSel.Power(idx_prev), 'omitnan');
                    if isnan(meanVal) || meanVal == 0
                        meanVal = 2500;  % Fallback-Wert [kW]
                    end
                    prevDayMean(idx_curr) = meanVal;
                end
            else
                nSteps = height(pvDataSel);
                prevDayMean = 2500 * ones(nSteps,1);
            end


            %% --- Kernberechnung ---------------------------------------
            residualResults = calculation.calcResidualLoads( ...
                normalDataSel, pvDataSel, dt, ...
                capacityBatt_kWh, pMaxBatt_kW, roundTripEff, ...
                useEV, capacityEV_kWh, pMaxEV_kW, ...
                numEV, prevDayMean, hpCount);

            %% --- Visualisierung ---------------------------------------
            analysis.plotQuartierResults( ...
                normalDataSel, pvDataSel, residualResults, zeitraumName, cw);
            disp('Plot fertig.');

            %% --- Folgeaktion ------------------------------------------
            nxt = menu('Weiter?', 'Zeitraum wechseln', 'Menü', 'Beenden');
            if nxt == 2       % zurück zum Quartier-Menü
                break;
            elseif nxt == 3   % Programm beenden
                return;
            end
        end  % Ende Zeitraum-Schleife
    end      % Ende Hauptschleife

    disp('Programm beendet.');
    close all;
end  % function mainSimulation
