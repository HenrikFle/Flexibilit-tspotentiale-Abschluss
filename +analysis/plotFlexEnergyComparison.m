function plotFlexEnergyComparison(flexTables, scenarioNames, zeitraumName, currentWeek, scenarioLabels)
%PLOTFLEXENERGYCOMPARISON Visualisiert Flex-Energieblöcke für mehrere Szenarien
%   plotFlexEnergyComparison(flexTables, scenarioNames, zeitraumName, currentWeek, scenarioLabels)
%   stellt die durchschnittlichen Lade- (Netzaufnahme) und Entladeanteile
%   (Netzentlastung) je Technologie farblich nach Szenario gegenüber.

if nargin < 5 || isempty(scenarioLabels)
    scenarioLabels = scenarioNames;
end

% Szenario-Bezeichner für Plot und Legende bereinigen ("Szenario"/"Scenario" entfernen)
plotLabels = regexprep(scenarioLabels, '^\s*(szenario|scenario)\s*', '', 'ignorecase');

if isempty(flexTables)
    warning('plotFlexEnergyComparison:NoData', ...
        'Keine Flexibilitätsdaten zur Darstellung vorhanden.');
    return;
end

numScenarios = numel(flexTables);
techNamesRef = flexTables{1}.names(:);
numTech = numel(techNamesRef);

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

    posMatrix(:,s) = posPlot(:);
    negMatrix(:,s) = negPlot(:);
end

scenarioColors = [0 0.45 0.74; 0.85 0.33 0.10; 0.47 0.67 0.19; 0.49 0.18 0.56];
scenarioColors = scenarioColors(1:numScenarios, :);

yBase = (1:numTech)';
barWidth = 0.24;
if numScenarios > 1
    offsetSpan = 0.28;
    offsets = linspace(-offsetSpan, offsetSpan, numScenarios);
else
    offsets = 0;
end

% Reihenfolge fix: oberste Position entspricht erstem Szenario-Eintrag
offsets = offsets(:)';

figure('Name','Flexibilitätspotenziale – Szenarienvergleich', ...
       'NumberTitle','off','Position',[680 80 1280 520]);
ax = gca;
hold(ax,'on');
grid(ax,'on');
xline(ax,0,'k--','HandleVisibility','off');

set(ax,'FontWeight','bold');
set(ax,'YDir','reverse');
set(ax,'YTick', yBase, 'YTickLabel', techNamesRef);

yMargin = max(0.45, (barWidth + max(abs(offsets))) * 1.2);
ylim(ax, [min(yBase) - yMargin, max(yBase) + yMargin]);

hScenario = gobjects(numScenarios,1);
for s = 1:numScenarios
    faceColor = scenarioColors(s,:);
    edgeColor = faceColor .* 0.75;

    posVals = max(posMatrix(:, s), 0);
    negVals = min(negMatrix(:, s), 0);
    yPos = yBase + offsets(s);

    if any(posVals)
        hPos = barh(ax, yPos, posVals, 'BarWidth', barWidth, ...
            'FaceColor', faceColor, 'EdgeColor', edgeColor, ...
            'LineWidth', 1.1);
        if ~isgraphics(hScenario(s))
            hScenario(s) = hPos(1);
        end
    end

    if any(negVals)
        hNeg = barh(ax, yPos, negVals, 'BarWidth', barWidth, ...
            'FaceColor', faceColor, 'EdgeColor', edgeColor, ...
            'LineWidth', 1.1);
        if ~isgraphics(hScenario(s))
            hScenario(s) = hNeg(1);
        end
    end
end

xlabel(ax,'Ø [kWh/Tag]  (<-- Netzentlastung | Netzbezug -->)','FontWeight','bold');

% --- Werte beschriften ----------------------------------------------------
xLimits = [min(negMatrix(:)), max(posMatrix(:))];
if ~any(isfinite(xLimits))
    xLimits = [-1, 1];
end
span = max(abs(xLimits));
if span <= 0
    span = 1;
end
textOffset = 0.02 * span;
labelPad = max(0.5, 0.2 * span);

xlim(ax, [xLimits(1) - (labelPad + textOffset), xLimits(2) + (labelPad + textOffset)]);

for t = 1:numTech
    baseY = yBase(t);

    % --- Positive Seite ---------------------------------------------------
    posRow = posMatrix(t,:);
    for s = 1:numScenarios
        posVal = posRow(s);
        if posVal > 0
            xTextPos = posVal + textOffset;
            text(ax, xTextPos, baseY + offsets(s), ...
                sprintf('%+d', round(posVal)), ...
                'HorizontalAlignment','left', 'VerticalAlignment','middle', ...
                'FontWeight','bold', 'Color', scenarioColors(s,:));
        end
    end

    % --- Negative Seite ---------------------------------------------------
    negRow = negMatrix(t,:);
    for s = 1:numScenarios
        negVal = negRow(s);
        if negVal < 0
            xTextNeg = negVal - textOffset;
            text(ax, xTextNeg, baseY + offsets(s), ...
                sprintf('%+d', round(negVal)), ...
                'HorizontalAlignment','right', 'VerticalAlignment','middle', ...
                'FontWeight','bold', 'Color', scenarioColors(s,:));
        end
    end
end

legendMask = isgraphics(hScenario);
if any(legendMask)
    legend(ax, hScenario(legendMask), plotLabels(legendMask), ...
           'Location','southoutside', 'NumColumns', numScenarios);
end

scenarioCaption = strjoin(scenarioNames, ', ');
sgtitle(sprintf('Flexibilitätspotenziale (%s) – %s', scenarioCaption, zeitraumName), ...
        'FontWeight','bold');

fprintf('\nFlex-Energieblöcke [%s | KW %d]\n', zeitraumName, currentWeek);
fprintf('-------------------------------------\n');
for t = 1:numTech
    fprintf('%s:\n', techNamesRef{t});
    for s = 1:numScenarios
        fprintf('  %-15s  Netzaufnahme: %+6.0f kWh   Netzentlastung: %+6.0f kWh\n', ...
                plotLabels{s}, posMatrix(t,s), -negMatrix(t,s));
    end
end

end