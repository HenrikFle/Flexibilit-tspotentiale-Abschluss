function plotFlexDailyProfilesComparison(residualResultsList, scenarioNames, zeitraumName, currentWeek, scenarioLabels)
%PLOTFLEXDAILYPROFILESCOMPARISON Visualisiert Tagesprofile der Flex-Technologien
%
%   Erstellt drei Mehrfach-Plots (Batterie, Wärmepumpe, EV) für alle
%   verfügbaren Szenarien. Jeder Plot enthält die Tagesprofile eines
%   Technologiestrangs übereinander zur direkten Gegenüberstellung.

if nargin < 5 || isempty(scenarioLabels)
    scenarioLabels = scenarioNames;
end

if isstring(scenarioNames);  scenarioNames  = cellstr(scenarioNames);  end
if isstring(scenarioLabels); scenarioLabels = cellstr(scenarioLabels); end
if ~iscell(scenarioNames);   scenarioNames  = {scenarioNames};  end
if ~iscell(scenarioLabels);  scenarioLabels = {scenarioLabels}; end

if isempty(residualResultsList)
    warning('plotFlexDailyProfilesComparison:NoData', ...
        'Keine Residuallast-Ergebnisse zur Darstellung vorhanden.');
    return;
end

numScenarios = numel(residualResultsList);

plotLabels = scenarioLabels(:);
for k = 1:numScenarios
    if k <= numel(plotLabels)
        plotLabels{k} = regexprep(string(plotLabels{k}), '^\s*(szenario|scenario)\s*', '', 'ignorecase');
    else
        plotLabels{k} = sprintf('Szenario %d', k);
    end
end
plotLabels = cellfun(@(c) char(strtrim(string(c))), plotLabels, 'UniformOutput', false);

scenarioData = repmat(struct( ...
    'time', datetime.empty(0,1), ...
    'residual', [], ...
    'batt', [], ...
    'ev', [], ...
    'wp', [], ...
    'dt', NaN, ...
    'label', '', ...
    't0', NaT, ...
    'pMaxBatt', NaN, ...
    'pMaxEV', NaN), numScenarios, 1);

for s = 1:numScenarios
    res = residualResultsList{s};

    if ~isstruct(res) || ~isfield(res, 'Timestamp') || isempty(res.Timestamp)
        scenarioData(s).label = plotLabels{min(s, numel(plotLabels))};
        continue;
    end

    seasonStart = determineSeasonDayStart(res.Timestamp(:), zeitraumName);
    [timeDay, idxDay, dayStart] = selectDay(res.Timestamp(:), seasonStart);

    if isempty(timeDay)
        scenarioData(s).label = plotLabels{min(s, numel(plotLabels))};
        continue;
    end

    battSeries     = extractField(res, 'pBatt_kW');
    evSeries       = extractField(res, 'pEV_flex');
    residualSeries = extractField(res, 'Residual_NoStorage');

    wpSeries = zeros(size(res.Timestamp(:)));
    if isfield(res, 'wpFlexAgg_kW') && isfield(res, 'wpAgg_kW')
        wpSeries = wpSeries + (res.wpFlexAgg_kW(:) - res.wpAgg_kW(:));
    end
    if isfield(res, 'dhwFlexAgg_kW') && isfield(res, 'dhwAgg_kW')
        wpSeries = wpSeries + (res.dhwFlexAgg_kW(:) - res.dhwAgg_kW(:));
    end

    battDay     = battSeries(idxDay);
    evDay       = evSeries(idxDay);
    residualDay = residualSeries(idxDay);
    wpDay       = wpSeries(idxDay);

    battDay(isnan(battDay))     = 0;
    evDay(isnan(evDay))         = 0;
    residualDay(isnan(residualDay)) = 0;
    wpDay(isnan(wpDay))         = 0;

    dtHours = NaN;
    if isfield(res, 'dtHours') && ~isempty(res.dtHours)
        dtHours = double(res.dtHours(1));
    end
    if ~isfinite(dtHours) || dtHours <= 0
        dtHours = estimateStepHours(timeDay);
    end

    scenarioData(s).time     = timeDay;
    scenarioData(s).residual = residualDay(:);
    scenarioData(s).batt     = battDay(:);
    scenarioData(s).ev       = evDay(:);
    scenarioData(s).wp       = wpDay(:);
    scenarioData(s).dt       = dtHours;
    scenarioData(s).label    = plotLabels{min(s, numel(plotLabels))};
    scenarioData(s).t0       = dayStart;
    if isfield(res, 'pMaxBatt_kW') && ~isempty(res.pMaxBatt_kW)
        scenarioData(s).pMaxBatt = double(res.pMaxBatt_kW(1));
    end
    if isfield(res, 'pMaxEV_kW') && ~isempty(res.pMaxEV_kW)
        scenarioData(s).pMaxEV = double(res.pMaxEV_kW(1));
    end
end

plotBatteryComparison(scenarioData, zeitraumName, currentWeek);
plotWPComparison(scenarioData, zeitraumName, currentWeek);
plotEVComparison(scenarioData, zeitraumName, currentWeek);

end

% -------------------------------------------------------------------------
function plotBatteryComparison(scenarioData, zeitraumName, currentWeek)

numScenarios = numel(scenarioData);
hasData = any(arrayfun(@(s) ~isempty(s.time), scenarioData));
if ~hasData
    return;
end

colChg = [0.05 0.10 0.55];   % Blau  – Netzaufnahme / Laden
colDis = [0.65 0.05 0.05];   % Rot   – Netzentlastung / Entladen
alpha  = 0.35;

fig = figure('Name', sprintf('%s – Tagesprofile Batterie', zeitraumName), ...
    'NumberTitle','off','Color','w', ...
    'Units','normalized','Position',[0.15 0.15 0.7 0.7]);

for s = 1:numScenarios
    ax = subplot(numScenarios, 1, s, 'Parent', fig);
    hold(ax, 'on'); grid(ax, 'on');
    ax.Box = 'on';

    timeVals = scenarioData(s).time;
    residual = scenarioData(s).residual;
    battVals = scenarioData(s).batt;
    dtHours  = scenarioData(s).dt;
    t0       = scenarioData(s).t0;
    label    = scenarioData(s).label;
    pMaxBatt = scenarioData(s).pMaxBatt;
    if ~isfinite(pMaxBatt) || pMaxBatt <= 0
        pMaxBatt = eps;
    else
        pMaxBatt = max(pMaxBatt, eps);
    end

    if isempty(timeVals)
        text(ax, 0.5, 0.5, 'Keine Daten verfügbar', ...
            'HorizontalAlignment','center', 'VerticalAlignment','middle', ...
            'FontAngle','italic');
        ax.XTickLabel = [];
        ylabel(ax, 'Leistung [kW]', 'FontWeight', 'bold');
        continue;
    end

    plot(ax, timeVals, residual, 'k-','LineWidth',1.4,'DisplayName','Residuallast');
    yline(ax, 0, 'k--','HandleVisibility','off');

    if ~isfinite(dtHours) || dtHours <= 0
        dtHours = estimateStepHours(timeVals);
    end

    Edis = sum(max(0, battVals)) * dtHours;
    Echg = -sum(min(0, battVals)) * dtHours;

    if Edis > 0 && pMaxBatt > 0
        tmp = timeVals;
        [~, iMax] = max(residual);
        tMax = tmp(max(iMax,1));
        half = hours((Edis / pMaxBatt) / 2);
        patch(ax, [tMax-half tMax+half tMax+half tMax-half], [0 0 -pMaxBatt -pMaxBatt], ...
            colDis, 'FaceAlpha', alpha, 'EdgeColor','none', ...
            'DisplayName', sprintf('Batterie entladen (−%.1f kWh)', Edis));
    end

    if Echg > 0 && pMaxBatt > 0
        tmp = timeVals;
        [~, iMin] = min(residual);
        tMin = tmp(max(iMin,1));
        half = hours((Echg / pMaxBatt) / 2);
        patch(ax, [tMin-half tMin+half tMin+half tMin-half], [0 0 pMaxBatt pMaxBatt], ...
            colChg, 'FaceAlpha', alpha, 'EdgeColor','none', ...
            'DisplayName', sprintf('Batterie laden (+%.1f kWh)', Echg));
    end

    negIdx = find(residual < 0);
    if ~isempty(negIdx) && Edis > 0 && Echg > 0
        tmp = timeVals;
        tL0 = tmp(negIdx(1));
        tL1 = tmp(negIdx(end)) + minutes(dtHours*60);
        Pchg = Echg / hours(tL1 - tL0);
        patch(ax, [tL0 tL1 tL1 tL0], [0 0 Pchg Pchg], ...
            colChg, 'FaceAlpha', alpha, 'EdgeColor','none', ...
            'HandleVisibility','off');

        tD0 = tL1;
        if isnat(t0)
            tD1 = timeVals(1) + days(1);
        else
            tD1 = t0 + days(1);
        end
        Pdis = -Edis / hours(tD1 - tD0);
        patch(ax, [tD0 tD1 tD1 tD0], [0 0 Pdis Pdis], ...
            colDis, 'FaceAlpha', alpha, 'EdgeColor','none', ...
            'HandleVisibility','off');
    end

    legend(ax, 'Location','best');
    ylabel(ax, 'Leistung [kW]', 'FontWeight','bold');

    if ~isnat(t0)
        xlim(ax, [t0, t0 + days(1)]);
    end

    datetick(ax,'x','HH:MM','keepticks','keeplimits');
    if s < numScenarios
        ax.XTickLabel = [];
    else
        xlabel(ax, 'Zeit','FontWeight','bold');
    end

    if ~isnat(t0)
        dateStr = datestr(t0,'dd-mmm');
    else
        dateStr = 'n/a';
    end
    title(ax, sprintf('%s (%s) – Batterie', label, dateStr), 'FontWeight','bold');
end

sgtitle(fig, sprintf('%s | KW %d – Batterie (Tagesprofil)', ...
    zeitraumName, currentWeek), 'FontWeight','bold');

end

% -------------------------------------------------------------------------
function plotWPComparison(scenarioData, zeitraumName, currentWeek)

numScenarios = numel(scenarioData);
hasData = any(arrayfun(@(s) ~isempty(s.time), scenarioData));
if ~hasData
    return;
end

colChg = [0.05 0.10 0.55];   % Netzaufnahme / Mehrverbrauch
colDis = [0.65 0.05 0.05];   % Netzentlastung / Einsparung
alpha  = 0.35;

fig = figure('Name', sprintf('%s – Tagesprofile Wärmepumpe', zeitraumName), ...
    'NumberTitle','off','Color','w', ...
    'Units','normalized','Position',[0.15 0.15 0.7 0.7]);

for s = 1:numScenarios
    ax = subplot(numScenarios, 1, s, 'Parent', fig);
    hold(ax, 'on'); grid(ax, 'on');
    ax.Box = 'on';

    timeVals = scenarioData(s).time;
    residual = scenarioData(s).residual;
    wpVals   = scenarioData(s).wp;
    dtHours  = scenarioData(s).dt;
    t0       = scenarioData(s).t0;
    label    = scenarioData(s).label;

    if isempty(timeVals)
        text(ax, 0.5, 0.5, 'Keine Daten verfügbar', ...
            'HorizontalAlignment','center', 'VerticalAlignment','middle', ...
            'FontAngle','italic');
        ax.XTickLabel = [];
        ylabel(ax, 'Leistung [kW]', 'FontWeight', 'bold');
        continue;
    end

    plot(ax, timeVals, residual, 'k-','LineWidth',1.4,'DisplayName','Residuallast');
    yline(ax, 0, 'k--','HandleVisibility','off');

    if ~isfinite(dtHours) || dtHours <= 0
        dtHours = estimateStepHours(timeVals);
    end

    Epos = sum(max(0, wpVals)) * dtHours;  % Mehrverbrauch
    Eneg = -sum(min(0, wpVals)) * dtHours; % Einsparung

    negIdx = find(residual < 0);
    if ~isempty(negIdx) && Epos > 0 && Eneg > 0
        tmp = timeVals;
        tPos0 = tmp(negIdx(1));
        tPos1 = tmp(negIdx(end)) + minutes(dtHours*60);
        Ppos = Epos / hours(tPos1 - tPos0);
        patch(ax, [tPos0 tPos1 tPos1 tPos0], [0 0 Ppos Ppos], ...
            colChg, 'FaceAlpha', alpha, 'EdgeColor','none', ...
            'DisplayName', sprintf('Mehrverbrauch (+%.1f kWh)', Epos));

        tNeg0 = tPos1;
        if isnat(t0)
            tNeg1 = timeVals(1) + days(1);
        else
            tNeg1 = t0 + days(1);
        end
        Pneg = -Eneg / hours(tNeg1 - tNeg0);
        patch(ax, [tNeg0 tNeg1 tNeg1 tNeg0], [0 0 Pneg Pneg], ...
            colDis, 'FaceAlpha', alpha, 'EdgeColor','none', ...
            'DisplayName', sprintf('Einsparung (−%.1f kWh)', Eneg));
    end

    legend(ax, 'Location','best');
    ylabel(ax, 'Leistung [kW]', 'FontWeight','bold');

    if ~isnat(t0)
        xlim(ax, [t0, t0 + days(1)]);
    end

    datetick(ax,'x','HH:MM','keepticks','keeplimits');
    if s < numScenarios
        ax.XTickLabel = [];
    else
        xlabel(ax, 'Zeit','FontWeight','bold');
    end

    if ~isnat(t0)
        dateStr = datestr(t0,'dd-mmm');
    else
        dateStr = 'n/a';
    end
    title(ax, sprintf('%s (%s) – Wärmepumpe', label, dateStr), 'FontWeight','bold');
end

sgtitle(fig, sprintf('%s | KW %d – Wärmepumpe (Tagesprofil)', ...
    zeitraumName, currentWeek), 'FontWeight','bold');

end

% -------------------------------------------------------------------------
function plotEVComparison(scenarioData, zeitraumName, currentWeek)

numScenarios = numel(scenarioData);
hasData = any(arrayfun(@(s) ~isempty(s.time), scenarioData));
if ~hasData
    return;
end

colChg = [0.05 0.10 0.55];   % Blau  – Laden
colDis = [0.65 0.05 0.05];   % Rot   – Entladen
alpha  = 0.35;

fig = figure('Name', sprintf('%s – Tagesprofile EV', zeitraumName), ...
    'NumberTitle','off','Color','w', ...
    'Units','normalized','Position',[0.15 0.15 0.7 0.7]);

for s = 1:numScenarios
    ax = subplot(numScenarios, 1, s, 'Parent', fig);
    hold(ax, 'on'); grid(ax, 'on');
    ax.Box = 'on';

    timeVals = scenarioData(s).time;
    residual = scenarioData(s).residual;
    evVals   = scenarioData(s).ev;
    dtHours  = scenarioData(s).dt;
    t0       = scenarioData(s).t0;
    label    = scenarioData(s).label;
    pMaxEV   = scenarioData(s).pMaxEV;
    if ~isfinite(pMaxEV) || pMaxEV <= 0
        pMaxEV = NaN;
    end

    if isempty(timeVals)
        text(ax, 0.5, 0.5, 'Keine Daten verfügbar', ...
            'HorizontalAlignment','center', 'VerticalAlignment','middle', ...
            'FontAngle','italic');
        ax.XTickLabel = [];
        ylabel(ax, 'Leistung [kW]', 'FontWeight', 'bold');
        continue;
    end

    plot(ax, timeVals, residual, 'k-','LineWidth',1.4,'DisplayName','Residuallast');
    yline(ax, 0, 'k--','HandleVisibility','off');

    if ~isfinite(dtHours) || dtHours <= 0
        dtHours = estimateStepHours(timeVals);
    end

    Edis = sum(max(0, evVals)) * dtHours;
    Echg = -sum(min(0, evVals)) * dtHours;

    if Edis > 0 && pMaxEV > 0
        tmp = timeVals;
        [~, iMax] = max(residual);
        tMax = tmp(max(iMax,1));
        avail = models.aggregatedEVChargingAvailability(hour(tMax) + minute(tMax)/60);
        Pmax = max(avail * pMaxEV, eps);
        half = hours((Edis / Pmax) / 2);
        patch(ax, [tMax-half tMax+half tMax+half tMax-half], [0 0 -Pmax -Pmax], ...
            colDis, 'FaceAlpha', alpha, 'EdgeColor','none', ...
            'DisplayName', sprintf('EV entladen (−%.1f kWh)', Edis));
    end

    if Echg > 0 && pMaxEV > 0
        tmp = timeVals;
        [~, iMin] = min(residual);
        tMin = tmp(max(iMin,1));
        avail = models.aggregatedEVChargingAvailability(hour(tMin) + minute(tMin)/60);
        Pmax = max(avail * pMaxEV, eps);
        half = hours((Echg / Pmax) / 2);
        patch(ax, [tMin-half tMin+half tMin+half tMin-half], [0 0 Pmax Pmax], ...
            colChg, 'FaceAlpha', alpha, 'EdgeColor','none', ...
            'DisplayName', sprintf('EV laden (+%.1f kWh)', Echg));
    end

    negIdx = find(residual < 0);
    if ~isempty(negIdx) && Edis > 0 && Echg > 0
        tmp = timeVals;
        tL0 = tmp(negIdx(1));
        tL1 = tmp(negIdx(end)) + minutes(dtHours*60);
        Pchg = Echg / hours(tL1 - tL0);
        patch(ax, [tL0 tL1 tL1 tL0], [0 0 Pchg Pchg], ...
            colChg, 'FaceAlpha', alpha, 'EdgeColor','none', ...
            'HandleVisibility','off');

        tD0 = tL1;
        if isnat(t0)
            tD1 = timeVals(1) + days(1);
        else
            tD1 = t0 + days(1);
        end
        Pdis = -Edis / hours(tD1 - tD0);
        patch(ax, [tD0 tD1 tD1 tD0], [0 0 Pdis Pdis], ...
            colDis, 'FaceAlpha', alpha, 'EdgeColor','none', ...
            'HandleVisibility','off');
    end

    legend(ax, 'Location','best');
    ylabel(ax, 'Leistung [kW]', 'FontWeight','bold');

    if ~isnat(t0)
        xlim(ax, [t0, t0 + days(1)]);
    end

    datetick(ax,'x','HH:MM','keepticks','keeplimits');
    if s < numScenarios
        ax.XTickLabel = [];
    else
        xlabel(ax, 'Zeit','FontWeight','bold');
    end

    if ~isnat(t0)
        dateStr = datestr(t0,'dd-mmm');
    else
        dateStr = 'n/a';
    end
    title(ax, sprintf('%s (%s) – EV', label, dateStr), 'FontWeight','bold');
end

sgtitle(fig, sprintf('%s | KW %d – EV (Tagesprofil)', ...
    zeitraumName, currentWeek), 'FontWeight','bold');

end

% -------------------------------------------------------------------------
function series = extractField(resStruct, fieldName)
if isfield(resStruct, fieldName)
    series = resStruct.(fieldName)(:);
else
    series = zeros(size(resStruct.Timestamp(:)));
end
end

% -------------------------------------------------------------------------
function [timeDay, idxDay, dayStart] = selectDay(timeVec, preferredStart)
timeDay = datetime.empty(0,1);
idxDay  = false(size(timeVec));
dayStart = NaT;

if isempty(timeVec)
    return;
end

if nargin >= 2 && ~isnat(preferredStart)
    t0 = preferredStart;
else
    t0 = dateshift(timeVec(1), 'start', 'day');
end

idx = (timeVec >= t0) & (timeVec < t0 + days(1));
if ~any(idx)
    t0 = dateshift(timeVec(1), 'start', 'day');
    idx = (timeVec >= t0) & (timeVec < t0 + days(1));
end

if ~any(idx)
    % Fallback: verwende ersten vollständigen Tag basierend auf erstem Zeitstempel
    t0 = dateshift(timeVec(1), 'start', 'day');
    idx = (timeVec >= t0) & (timeVec < t0 + days(1));
    if ~any(idx)
        % letzte Rückfallebene – nutze die ersten 96 Werte (24h à 15 min)
        n = min(numel(timeVec), 96);
        idx(1:n) = true;
        t0 = timeVec(find(idx,1,'first'));
    end
end

timeDay = timeVec(idx);
idxDay  = idx;
dayStart = t0;
end

% -------------------------------------------------------------------------
function dtHours = estimateStepHours(timeVals)
if numel(timeVals) < 2
    dtHours = 1;
    return;
end
diffVals = diff(timeVals);
dtHours = hours(median(diffVals, 'omitnan'));
if ~isfinite(dtHours) || dtHours <= 0
    dtHours = 1;
end
end

% -------------------------------------------------------------------------
function seasonStart = determineSeasonDayStart(timeVec, zeitraumName)
seasonStart = NaT;

if nargin < 1 || isempty(timeVec)
    return;
end

try
    yr = year(timeVec(1));
catch
    seasonStart = NaT;
    return;
end

seasonName = lower(strtrim(char(zeitraumName)));
switch seasonName
    case 'winter'
        candidate = datetime(yr, 1, 8);
    case {'sommer','summer'}
        candidate = datetime(yr, 6, 28);
    case {'übergangszeit','uebergangszeit','transition'}
        candidate = datetime(yr, 9, 6);
    otherwise
        candidate = NaT;
end

if ~isnat(candidate)
    hasDay = any(timeVec >= candidate & timeVec < candidate + days(1));
    if hasDay
        seasonStart = candidate;
        return;
    end
end

seasonStart = dateshift(timeVec(1), 'start', 'day');
end