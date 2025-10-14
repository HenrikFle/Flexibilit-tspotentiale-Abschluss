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
                              'Alle Szenarien', ...
                              'Exit');
        if scenarioChoice == 0 || scenarioChoice == 5
            break;   % Abbruch über X/Exit
        end

        scenarioLabelsAll = {'Aktuelles Szenario','Szenario 2030','Szenario 2050'};
        scenarioNamesAll  = {'Aktuell','2030','2050'};
        if scenarioChoice == 4
            scenarioList = 1:3;
        else
            scenarioList = scenarioChoice;
        end
        scenarioLabels = scenarioLabelsAll;
        scenarioNames  = scenarioNamesAll;
        runAllScenarios = numel(scenarioList) > 1;

        %% 5.3) Quartier via Menü wählen ---------------------------------
        quartierChoice = menu('Wähle Quartier:', ...
                              'Quartier 1: Stadtquartier (Verl)', ...
                              'Quartier 2: Innenstädtisches Quartier (Berlin-Mitte)', ...
                              'Quartier 3: Ländliches Quartier (Neuhof (Sundhagen))', ...
                              'Exit');
        if quartierChoice == 0 || quartierChoice == 4   % Abbruch über X/Exit
            break;
        end

        %% 5.5) Quartiersbezogene Datenaufbereitung (grundsätzlich) -------
        quartierLoadBase = [];
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

                quartierLoadBase = merged3;   % Speichern für spätere Gewichtung

            otherwise
                break;   % sollte nicht auftreten
        end

        if isempty(quartierLoadBase)
            warning('Keine Quartiersdaten verfügbar – zurück zum Hauptmenü.');
            continue;
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

            flexTables = cell(1, numel(scenarioList));
            residualResultsAll = cell(1, numel(scenarioList));
            scenarioRan = false;
            sharedFlexBounds = struct();

            needReferenceBounds = ~ismember(1, scenarioList);

            if needReferenceBounds
                [refOk, refInputs] = prepareScenarioInputs(1);
                if refOk
                    paramsRef = refInputs.params;
                    try
                        refResults = calculation.calcResidualLoads( ...
                            refInputs.normalDataSel, refInputs.pvDataSel, dt, ...
                            paramsRef.capacityBatt_kWh, paramsRef.pMaxBatt_kW, paramsRef.roundTripEff, ...
                            paramsRef.useEV, paramsRef.capacityEV_kWh, paramsRef.pMaxEV_kW, ...
                            paramsRef.numEV, paramsRef.flexWindowDays, paramsRef.flexStdMultiplier, ...
                            paramsRef.hpCount, struct());

                        sharedFlexBounds.lower    = refResults.flexLowerBound_kW;
                        sharedFlexBounds.upper    = refResults.flexUpperBound_kW;
                        sharedFlexBounds.baseline = refResults.flexBaseline_kW;
                        sharedFlexBounds.spread   = refResults.flexSpread_kW;
                    catch err
                        warning('Referenzgrenzen konnten nicht berechnet werden: %s', err.message);
                        sharedFlexBounds = struct();
                    end
                else
                    warning('Referenzgrenzen (Aktuelles Szenario) nicht verfügbar – es werden Szenarioeigene Grenzen genutzt.');
                end
            end

            for sIdx = 1:numel(scenarioList)
                sc = scenarioList(sIdx);
                [dataOk, scenarioInputs] = prepareScenarioInputs(sc);
                if ~dataOk
                    continue;
                end

                params = scenarioInputs.params;
                normalDataSel = scenarioInputs.normalDataSel;
                pvDataSel     = scenarioInputs.pvDataSel;

                roundTripEff     = params.roundTripEff;
                useEV            = params.useEV;
                numEV            = params.numEV;
                capacityEV_kWh   = params.capacityEV_kWh;
                pMaxEV_kW        = params.pMaxEV_kW;
                capacityBatt_kWh = params.capacityBatt_kWh;
                pMaxBatt_kW      = params.pMaxBatt_kW;
                hpCount          = params.hpCount;

                %% --- Kernberechnung -----------------------------------
                if runAllScenarios && isfield(sharedFlexBounds, 'lower') && ...
                        ~isempty(sharedFlexBounds.lower)
                    overrideBounds = sharedFlexBounds;
                elseif ~runAllScenarios && needReferenceBounds && ...
                        isfield(sharedFlexBounds,'lower') && ~isempty(sharedFlexBounds.lower)
                    overrideBounds = sharedFlexBounds;
                else
                    overrideBounds = struct();
                end

                residualResults = calculation.calcResidualLoads( ...
                    normalDataSel, pvDataSel, dt, ...
                    capacityBatt_kWh, pMaxBatt_kW, roundTripEff, ...
                    useEV, capacityEV_kWh, pMaxEV_kW, ...
                    numEV, params.flexWindowDays, params.flexStdMultiplier, ...
                    hpCount, overrideBounds);

                scenarioRan = true;

                if (runAllScenarios || (~runAllScenarios && sc == 1)) && ...
                        ~(isfield(sharedFlexBounds,'lower') && ~isempty(sharedFlexBounds.lower))
                    sharedFlexBounds.lower    = residualResults.flexLowerBound_kW;
                    sharedFlexBounds.upper    = residualResults.flexUpperBound_kW;
                    sharedFlexBounds.baseline = residualResults.flexBaseline_kW;
                    sharedFlexBounds.spread   = residualResults.flexSpread_kW;
                end

                if runAllScenarios
                    flexTables{sIdx} = residualResults.flexEnergyTable;
                    residualResultsAll{sIdx} = residualResults;
                else
                    %% --- Visualisierung (Einzelszenario) ---------------
                    analysis.plotQuartierResults( ...
                        normalDataSel, pvDataSel, residualResults, zeitraumName, cw);
                end
            end

            if ~scenarioRan
                continue;  % kein Szenario erfolgreich -> zurück zur Auswahl
            end

            if runAllScenarios
                validIdx = ~cellfun(@isempty, flexTables);
                flexTables = flexTables(validIdx);
                residualResultsAll = residualResultsAll(validIdx);
                scenarioNamesSel  = scenarioNames(validIdx);
                scenarioLabelsSel = scenarioLabels(scenarioList(validIdx));
                if isempty(flexTables)
                    fprintf('Keine gültigen Ergebnisse für %s / KW %d verfügbar.\n', ...
                            zeitraumName, cw);
                else
                    analysis.plotFlexEnergyComparison(flexTables, scenarioNamesSel, ...
                        zeitraumName, cw, scenarioLabelsSel);
                    if ~isempty(residualResultsAll)
                        analysis.plotFlexDailyProfilesComparison(residualResultsAll, ...
                            scenarioNamesSel, zeitraumName, cw, scenarioLabelsSel);
                    end
                    disp('Plot fertig (Szenarienvergleich).');
                end
            else
                disp('Plot fertig.');
            end

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

    function [ok, scenarioInputs] = prepareScenarioInputs(sc)
        scenarioInputs = struct();

        paramsLocal = config.getScenarioParams(sc, quartierChoice);
        scenarioInputs.params = paramsLocal;

        buildingWeightsLocal = paramsLocal.buildingWeights;
        sumW = quartierLoadBase.Power               * buildingWeightsLocal.EFH + ...
               quartierLoadBase.Power_dataMFH_k     * buildingWeightsLocal.MFH_k + ...
               quartierLoadBase.Power_dataMFH_m     * buildingWeightsLocal.MFH_m + ...
               quartierLoadBase.Power_dataMFH_g     * buildingWeightsLocal.MFH_g;

        normalDataLocal = table(quartierLoadBase.Timestamp, sumW*1e-3, ...
                                'VariableNames', {'Timestamp','Power'});

        pvDataLocal = pvDataRaw;

        ND = normalDataLocal(ismember(month(normalDataLocal.Timestamp), months), :);
        if ~isempty(ND), ND.KW = week(ND.Timestamp); end
        normalDataSelLocal = ND(ND.KW == cw, :);

        PD = pvDataLocal(ismember(month(pvDataLocal.Timestamp), months), :);
        if ~isempty(PD), PD.KW = week(PD.Timestamp); end
        pvDataSelRawLocal = PD(PD.KW == cw, :);
        if ~isempty(pvDataSelRawLocal)
            pvDataSelLocal       = pvDataSelRawLocal;
            pvDataSelLocal.Power = pvDataSelLocal.Power * paramsLocal.pvScaleMWp;
        else
            pvDataSelLocal = pvDataSelRawLocal;  % leer, gleiche Struktur
        end

        scenarioInputs.normalDataSel = normalDataSelLocal;
        scenarioInputs.pvDataSel     = pvDataSelLocal;

        if isempty(normalDataSelLocal) && isempty(pvDataSelLocal)
            fprintf('Keine Daten für %s / KW %d im %s.\n', ...
                    zeitraumName, cw, scenarioLabelsAll{sc});
            ok = false;
        else
            ok = true;
        end
    end
end  % function mainSimulation
