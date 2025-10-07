function plotFlexEnergyComparison(flexTables, scenarioNames, zeitraumName, currentWeek, scenarioLabels)
%PLOTFLEXENERGYCOMPARISON Visualisiert Flex-Energieblöcke für mehrere Szenarien
%   plotFlexEnergyComparison(flexTables, scenarioNames, zeitraumName, currentWeek, scenarioLabels)
%   stellt die durchschnittlichen Lade- (Netzaufnahme) und Entladeanteile
%   (Netzentlastung) je Technologie farblich nach Szenario gegenüber.

if nargin < 5 || isempty(scenarioLabels)
    scenarioLabels = scenarioNames;
end

% Szenario-Bezeichner für Plot und Legende bereinigen ("Szenario"/"Scenario" entfernen)
plotLabels = regexprep(scenarioLabels, '^(?i)\s*(szenario|scenario)\s*', '');

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
drawOrder      = numScenarios:-1:1;  % zeichne größte Szenarien zuerst

techCats = categorical(techNamesRef, techNamesRef, 'Ordinal', true);

figure('Name','Flexibilitätspotenziale – Szenarienvergleich', ...
       'NumberTitle','off','Position',[680 80 1280 520]);
ax = gca;
hold(ax,'on');
grid(ax,'on');
xline(ax,0,'k--','HandleVisibility','off');

set(ax,'FontWeight','bold');
set(ax,'YDir','reverse');

hScenario = gobjects(numScenarios,1);
for idx = 1:numScenarios
    s = drawOrder(idx);
    posVals = posMatrix(:, s);
    negVals = negMatrix(:, s);

    posColor = scenarioColors(s,:);
    negColor = scenarioColors(s,:);

    barh(ax, techCats, negVals, 'BarWidth',0.6, ...
        'FaceColor', negColor, 'EdgeColor', negColor .* 0.8, ...
        'LineWidth', 1.1);
    hPos = barh(ax, techCats, posVals, 'BarWidth',0.6, ...
        'FaceColor', posColor, 'EdgeColor', posColor .* 0.8, ...
        'LineWidth', 1.1);

    if isempty(hScenario(s)) || ~isgraphics(hScenario(s))
        hScenario(s) = hPos;
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

yIdx = double(techCats);
anchorIdx = find(contains(lower(plotLabels), '2050'), 1, 'last');
if isempty(anchorIdx)
    anchorIdx = numScenarios;
end

ySpacing = 0.16;
for t = 1:numTech
    baseY = yIdx(t);

    % --- Positive Seite ---------------------------------------------------
    posAnchorVal = posMatrix(t, anchorIdx);
    if posAnchorVal <= 0
        posAnchorVal = max(posMatrix(t,:));
    end
    if posAnchorVal > 0
        xTextPos = posAnchorVal + textOffset;
        yStartPos = baseY + (numScenarios-1)/2 * ySpacing;
        for s = 1:numScenarios
            posVal = posMatrix(t,s);
            if posVal > 0
                yPos = yStartPos - (s-1) * ySpacing;
                text(ax, xTextPos, yPos, ...
                    sprintf('%+.1f', posVal), ...
                    'HorizontalAlignment','left', 'VerticalAlignment','middle', ...
                    'FontWeight','bold', 'Color', scenarioColors(s,:));
            end
        end
    end

    % --- Negative Seite ---------------------------------------------------
    negAnchorVal = negMatrix(t, anchorIdx);
    if negAnchorVal >= 0
        negAnchorVal = min(negMatrix(t,:));
    end
    if negAnchorVal < 0
        xTextNeg = negAnchorVal - textOffset;
        yStartNeg = baseY - (numScenarios-1)/2 * ySpacing;
        for s = 1:numScenarios
            negVal = negMatrix(t,s);
            if negVal < 0
                yPos = yStartNeg + (s-1) * ySpacing;
                text(ax, xTextNeg, yPos, ...
                    sprintf('%+.1f', negVal), ...
                    'HorizontalAlignment','right', 'VerticalAlignment','middle', ...
                    'FontWeight','bold', 'Color', scenarioColors(s,:));
            end
        end
    end
end

legend(ax, hScenario, plotLabels, 'Location','southoutside', ...
       'NumColumns', numScenarios);

scenarioCaption = strjoin(scenarioNames, ', ');
sgtitle(sprintf('Flexibilitätspotenziale (%s) – %s', scenarioCaption, zeitraumName), ...
        'FontWeight','bold');

fprintf('\nFlex-Energieblöcke [%s | KW %d]\n', zeitraumName, currentWeek);
fprintf('-------------------------------------\n');
for t = 1:numTech
    fprintf('%s:\n', techNamesRef{t});
    for s = 1:numScenarios
        fprintf('  %-15s  Netzaufnahme: %+6.1f kWh   Netzentlastung: %+6.1f kWh\n', ...
                plotLabels{s}, posMatrix(t,s), -negMatrix(t,s));
    end
end

end