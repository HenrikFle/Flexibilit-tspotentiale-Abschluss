% Datei: +data_import/readAndPreprocessData.m
function [dataEFH, dataMFH_k, dataMFH_m, dataMFH_g, pvDataRaw, ...
          winterMonths, sommerMonths, uebergangszeitMonths] = readAndPreprocessData()
% readAndPreprocessData  Datenimport & Vorverarbeitung
% -------------------------------------------------------------------------
% Liest Verbrauchs- und PV-CSV-Dateien ein, skaliert sie entsprechend der 
% Gebäudetypen und vereinheitlicht Zeitstempel für das Quartiersmodell.
%
% Outputs:
%   dataEFH             Einfamilienhaus-Last (Timestamp, Power [kW])
%   dataMFH_k           Kleine Mehrfamilienhäuser-Last
%   dataMFH_m           Mittlere Mehrfamilienhäuser-Last
%   dataMFH_g           Große Mehrfamilienhäuser-Last
%   pvDataRaw           Originale PV-Leistungstabelle (Timestamp, Power)
%   winterMonths        Indizes der Wintermonate [12,1,2]
%   sommerMonths        Indizes der Sommermonate [6,7,8]
%   uebergangszeitMonths Indizes der Übergangsmonate [3,4,5,9,10,11]
% -------------------------------------------------------------------------

%% Einfamilienhaus (EFH)
fileEFH = 'LP_W_EFH.csv';
optsEFH = detectImportOptions(fileEFH, 'Delimiter', ',', 'VariableNamingRule', 'preserve');
tabEFH = readtable(fileEFH, optsEFH);
% Zeitstempel parsen und Zeitzone entfernen
tabEFH.Timestamp = datetime(tabEFH{:,1}, 'InputFormat','yyyy-MM-dd HH:mm:ssZZZZZ', 'TimeZone', 'Europe/Berlin');
tabEFH.Timestamp.TimeZone = '';
% Skalieren auf Gesamtenergie (5 kWh pro Einheit im Zeitraster)
tabEFH.Power = tabEFH{:,2} * 5;
% Sortieren und selektieren
tabEFH = sortrows(tabEFH, 'Timestamp');
dataEFH = table(tabEFH.Timestamp, tabEFH.Power, 'VariableNames', {'Timestamp', 'Power'});

%% Kleine Mehrfamilienhäuser (MFH_k)
fileMFHk = 'LP_W_MFH_k.csv';
optsK = detectImportOptions(fileMFHk, 'Delimiter', ',', 'VariableNamingRule', 'preserve');
tabK = readtable(fileMFHk, optsK);
tabK.Timestamp = datetime(tabK{:,1}, 'InputFormat','yyyy-MM-dd HH:mm:ssZZZZZ', 'TimeZone', 'Europe/Berlin');
tabK.Timestamp.TimeZone = '';
tabK.Power = tabK{:,2} * 10;
tabK = sortrows(tabK, 'Timestamp');
dataMFH_k = table(tabK.Timestamp, tabK.Power, 'VariableNames', {'Timestamp', 'Power'});

%% Mittlere Mehrfamilienhäuser (MFH_m)
fileMFHm = 'LP_W_MFH_m.csv';
optsM = detectImportOptions(fileMFHm, 'Delimiter', ',', 'VariableNamingRule', 'preserve');
tabM = readtable(fileMFHm, optsM);
tabM.Timestamp = datetime(tabM{:,1}, 'InputFormat','yyyy-MM-dd HH:mm:ssZZZZZ', 'TimeZone', 'Europe/Berlin');
tabM.Timestamp.TimeZone = '';
tabM.Power = tabM{:,2} * 30;
tabM = sortrows(tabM, 'Timestamp');
dataMFH_m = table(tabM.Timestamp, tabM.Power, 'VariableNames', {'Timestamp', 'Power'});

%% Große Mehrfamilienhäuser (MFH_g)
fileMFHg = 'LP_W_MFH_g.csv';
optsG = detectImportOptions(fileMFHg, 'Delimiter', ',', 'VariableNamingRule', 'preserve');
tabG = readtable(fileMFHg, optsG);
tabG.Timestamp = datetime(tabG{:,1}, 'InputFormat','yyyy-MM-dd HH:mm:ssZZZZZ', 'TimeZone', 'Europe/Berlin');
tabG.Timestamp.TimeZone = '';
tabG.Power = tabG{:,2} * 72.5;
tabG = sortrows(tabG, 'Timestamp');
dataMFH_g = table(tabG.Timestamp, tabG.Power, 'VariableNames', {'Timestamp', 'Power'});

%% PV-Daten (Zeitverschiebung + Skalierung)
pvFile = 'pv_1_a_2015.csv';
optsPV = detectImportOptions(pvFile, 'Delimiter', ',', 'VariableNamingRule', 'preserve');
pvTab = readtable(pvFile, optsPV);
% Zeitstempel parsen und Jahre anpassen (2015 → 2019)
pvTab.Timestamp = datetime(pvTab{:,1}, 'InputFormat','yyyy-MM-dd HH:mm:ssZZZZZ','TimeZone','Europe/Berlin');
oldYears = year(pvTab.Timestamp);
shift = 2019 - 2015;
newYears = oldYears + shift;
pvTab.Timestamp = datetime(newYears, month(pvTab.Timestamp), day(pvTab.Timestamp), ...
                           hour(pvTab.Timestamp), minute(pvTab.Timestamp), second(pvTab.Timestamp));
% Leistungsdaten extrahieren und sortieren
pvTab.Power = pvTab.('025-east-west_075-south [W/kWp]');
pvTab = sortrows(pvTab, 'Timestamp');
pvDataRaw = table(pvTab.Timestamp, pvTab.Power, 'VariableNames', {'Timestamp','Power'});

%% Monatsbereiche definieren
winterMonths = [12,1,2];
sommerMonths = [6,7,8];
uebergangszeitMonths = [3,4,5,9,10,11];

end
