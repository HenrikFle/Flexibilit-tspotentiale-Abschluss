function plotFlexEnergyComparison(flexTables, scenarioNames, zeitraumName, currentWeek, scenarioLabels)
%PLOTFLEXENERGYCOMPARISON Visualisiert Flex-Energieblöcke für mehrere Szenarien

% --- Eingaben normalisieren ---------------------------------------------
if nargin < 5 || isempty(scenarioLabels)
    scenarioLabels = scenarioNames;
end
if isstring(scenarioNames);  scenarioNames  = cellstr(scenarioNames);  end
if isstring(scenarioLabels); scenarioLabels = cellstr(scenarioLabels); end
if ~iscell(scenarioNames);  scenarioNames  = {scenarioNames};  end
if ~iscell(scenarioLabels); scenarioLabels = {scenarioLabels}; end

% Szenario-Bezeichner bereinigen ("Szenario"/"Scenario" entfernen)
plotLabels = regexprep(scenarioLabels, '^\s*(szenario|scenario)\s*', '', 'ignorecase');

if isempty(flexTables)
    warning('plotFlexEnergyComparison:NoData', ...
        'Keine Flexibilitätsdaten zur Darstellung vorhanden.');
    return;
end

% --- Referenz-Technologieliste ------------------------------------------
numScenarios = numel(flexTables);

% Mapping für Y-Achse
yLabelMap = containers.Map( ...
    {'EV','Wärmepumpe','Batterie'}, ...
    {'Elektrofahrzeuge','Wärmepumpe','Batteriespeicher'} );

techNamesRef = flexTables{1}.names(:);
techNamesRef = cellfun(@(c) char(strtrim(string(c))), techNamesRef, 'UniformOutput', false);

yTickLabels = techNamesRef;
for t = 1:numel(techNamesRef)
    key = techNamesRef{t};
    if isKey(yLabelMap, key)
        yTickLabels{t} = yLabelMap(key);
    else
        yTickLabels{t} = key;
    end
end
yTickLabels = yTickLabels(:);
numTech = numel(techNamesRef);

% --- Datenmatrix ---------------------------------------------------------
posMatrix = zeros(numTech, numScenarios);
negMatrix = zeros(numTech, numScenarios);
for s = 1:numScenarios
    ft = flexTables{s};
    [tf, idx] = ismember(techNamesRef, ft.names(:));
    if ~all(tf)
        error('plotFlexEnergyComparison:NameMismatch', ...
              'Technologie-Listen der Szenarien stimmen nicht überein.');
    end
    posPlot = ft.Epos_kWh(idx);
    negPlot = ft.Eneg_kWh(idx);

    swapIdx = ismember(techNamesRef, {'Batterie','EV'});
    posPlot(swapIdx) = -ft.Eneg_kWh(idx(swapIdx));
    negPlot(swapIdx) = -ft.Epos_kWh(idx(swapIdx));

    posMatrix(:, s) = posPlot(:);
    negMatrix(:, s) = negPlot(:);
end

% --- Farben (gut unterscheidbar, farbenblind-freundlich) -----------------
scenarioColors = [
    51   102 204   % Blau
   220    50  32   % Rot
    35   139  69   % Grün
   255   127   0   % Orange
   117   112 179   % Violett
] ./ 255;
scenarioColors = scenarioColors(1:numScenarios, :);

yBase = (1:numTech)';
barWidth = 0.24;
if numScenarios > 1
    offsetSpan = 0.28;
    offsets = linspace(-offsetSpan, offsetSpan, numScenarios);
else
    offsets = 0;
end
offsets = offsets(:)';

% --- Figure/Axes ---------------------------------------------------------
figure('Name','Flexibilitätspotenziale – Szenarienvergleich', ...
       'NumberTitle','off', ...
       'Color','w', ...
       'Units','centimeters', ...
       'Position',[2 2 16 9.5], ...
       'PaperUnits','centimeters', ...
       'PaperPosition',[0 0 16 9.5], ...
       'PaperSize',[16 9.5]);
ax = gca;
hold(ax,'on');
ax.FontName  = 'Times New Roman';
ax.FontSize  = 11;
ax.FontWeight = 'normal';

grid(ax,'on');
xline(ax,0,'k--','HandleVisibility','off');
ax.XGrid = 'on';
ax.YGrid = 'off';
ax.GridColor = 0.92.*[1 1 1];

set(ax,'YDir','reverse');
set(ax,'YTick', yBase, 'YTickLabel', yTickLabels);

yMargin = max(0.45, (barWidth + max(abs(offsets))) * 1.2);
ylim(ax, [min(yBase) - yMargin, max(yBase) + yMargin]);

% --- Balken --------------------------------------------------------------
hScenario = gobjects(numScenarios,1);
for s = 1:numScenarios
    faceColor = scenarioColors(s,:);
    edgeColor = faceColor .* 0.75;
    posVals = max(posMatrix(:, s), 0);
    negVals = min(negMatrix(:, s), 0);
    yPos = yBase + offsets(s);

    if any(posVals)
        hPos = barh(ax, yPos, posVals, 'BarWidth', barWidth, ...
            'FaceColor', faceColor, 'EdgeColor', edgeColor, 'LineWidth', 1.1);
        if ~isgraphics(hScenario(s)), hScenario(s) = hPos(1); end
    end
    if any(negVals)
        hNeg = barh(ax, yPos, negVals, 'BarWidth', barWidth, ...
            'FaceColor', faceColor, 'EdgeColor', edgeColor, 'LineWidth', 1.1);
        if ~isgraphics(hScenario(s)), hScenario(s) = hNeg(1); end
    end
end

xlabel(ax,'Mittelwert pro Tag [kWh/Tag] (links: Netzentlastung, rechts: Netzbezug)', ...
    'FontName','Times New Roman', 'FontSize',12, 'FontWeight','bold');

% --- Achsenskalierung & Labels ------------------------------------------
xLimits = [min(negMatrix(:)), max(posMatrix(:))];
if ~any(isfinite(xLimits)), xLimits = [-1, 1]; end
span = max(abs(xLimits));
if span <= 0, span = 1; end
tickStep = 10000;
tickMax  = max(tickStep, ceil(span / tickStep) * tickStep);
tickValues = -tickMax:tickStep:tickMax;

xticks(ax, tickValues);
xticklabels(ax, arrayfun(@localFormatThousand, tickValues, 'UniformOutput', false));
ax.XAxis.Exponent = 0;

textOffset = 0.02 * tickMax;
labelPad   = max(0.5, 0.15 * tickMax);
xlim(ax, [-(tickMax + labelPad), tickMax + labelPad]);

% --- Wertbeschriftungen --------------------------------------------------
for t = 1:numTech
    baseY = yBase(t);
    posRow = posMatrix(t,:);
    for s = 1:numScenarios
        posVal = posRow(s);
        if posVal > 0
            text(ax, posVal + textOffset, baseY + offsets(s), ...
                localFormatThousand(posVal), ...
                'HorizontalAlignment','left','VerticalAlignment','middle', ...
                'FontName','Times New Roman','FontSize',14, ...
                'FontWeight','bold','Color', scenarioColors(s,:));
        end
    end
    negRow = negMatrix(t,:);
    for s = 1:numScenarios
        negVal = negRow(s);
        if negVal < 0
            text(ax, negVal - textOffset, baseY + offsets(s), ...
                localFormatThousand(negVal), ...
                'HorizontalAlignment','right','VerticalAlignment','middle', ...
                'FontName','Times New Roman','FontSize',14, ...
                'FontWeight','bold','Color', scenarioColors(s,:));
        end
    end
end

% --- Legende & Titel -----------------------------------------------------
legendMask = isgraphics(hScenario);
if any(legendMask)
    lgd = legend(ax, hScenario(legendMask), plotLabels(legendMask), ...
           'Location','southoutside','NumColumns', numScenarios, ...
           'Orientation','horizontal','Box','off');
    set(lgd,'FontName','Times New Roman','FontSize',11);
end

scenarioCaption = strjoin(scenarioNames, ', ');
sgt = sgtitle(sprintf('Flexibilitätspotenziale (%s) – %s', scenarioCaption, zeitraumName));
set(sgt,'FontName','Times New Roman','FontSize',14,'FontWeight','bold');

% --- Konsole -------------------------------------------------------------
fprintf('\nFlex-Energieblöcke [%s | KW %d]\n', zeitraumName, currentWeek);
fprintf('-------------------------------------\n');
for t = 1:numTech
    fprintf('%s:\n', yTickLabels{t});
    for s = 1:numScenarios
        fprintf('  %-15s  Netzaufnahme: %8s kWh   Netzentlastung: %8s kWh\n', ...
                plotLabels{s}, ...
                localFormatThousand(max(posMatrix(t,s), 0)), ...
                localFormatThousand(max(-negMatrix(t,s), 0)));
    end
end

    function txt = localFormatThousand(value)
        if ~isfinite(value), txt = ''; return; end
        signStr = '';
        if value < 0, signStr = '-'; end
        absValue = abs(round(value));
        core = sprintf('%0.0f', absValue);
        core = regexprep(core,'(?<=\d)(?=(\d{3})+(?!\d))',' ');
        if isempty(core), core = '0'; end
        txt = [signStr core];
    end
end
