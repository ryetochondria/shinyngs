#' The input function of the boxplot module
#' 
#' This module produces displays of the quartiles of the values in the 
#' selected assay matrix. For low sample numbers (<= 20) the default is a 
#' boxplot produced using \code{ggplot2}. For higher sample numbers, the default is
#' a line-based alternative using \code{plotly}.
#' 
#' @param id Submodule namespace
#' @param eselist ExploratorySummarizedExperimentList object containing
#'   ExploratorySummarizedExperiment objects
#'   
#' @return output An HTML tag object that can be rendered as HTML using 
#'   as.character()
#'   
#' @keywords shiny
#'   
#' @examples
#' boxplotInput(ns('boxplot'), eselist)
#' 
#' # Almost certainly used via application creation
#' 
#' data(zhangneurons)
#' app <- prepareApp('boxplot', zhangneurons)
#' shiny::shinyApp(ui = app$ui, server = app$server)

boxplotInput <- function(id, eselist) {
    ns <- NS(id)
    
    default_type <- "boxes"
    if (ncol(eselist[[1]]) > 50) {
        default_type <- "lines"
    }
    
    expression_filters <- selectmatrixInput(ns("sampleBoxplot"), eselist)
    quartile_plot_filters <- list(radioButtons(ns("plotType"), "Plot type", c("boxes", "lines"), selected = default_type), numericInput(ns("whiskerDistance"), 
        "Whisker distance in multiples of IQR", value = 1.5), groupbyInput(ns("boxplot")))
    
    field_sets = list()
    naked_fields = list()  # Things we don't want to wrap in a field set - probably hidden stuff
    
    # Don't create an empty field set if we're not grouping
    
    if (length(eselist@group_vars) > 0) {
        field_sets$quartile_plot_filters <- quartile_plot_filters
    } else {
        naked_fields[[1]] <- quartile_plot_filters
    }
    
    field_sets <- c(field_sets, list(expression = expression_filters, export = plotdownloadInput(ns("boxplot"), "box plot")))
    
    list(naked_fields, fieldSets(ns("fieldset"), field_sets))
}

#' The output function of the boxplot module
#' 
#' This module produces displays of the quartiles of the values in the 
#' selected assay matrix. For low sample numbers (<= 20) the default is a 
#' boxplot produced using \code{ggplot2}. For higher sample numbers, the default is
#' a line-based alternative using \code{plotly}.
#'
#' @param id Submodule namespace
#'
#' @return output An HTML tag object that can be rendered as HTML using 
#' as.character() 
#'
#' @keywords shiny
#' 
#' @examples
#' boxplotOutput('boxplot')
#' 
#' # Almost certainly used via application creation
#' 
#' data(zhangneurons)
#' app <- prepareApp('boxplot', zhangneurons)
#' shiny::shinyApp(ui = app$ui, server = app$server)

boxplotOutput <- function(id) {
    ns <- NS(id)
    list(modalInput(ns("boxplot"), "help", "help"), modalOutput(ns("boxplot"), "Quartile plots", includeMarkdown(system.file("inlinehelp", "boxplot.md", package = packageName()))), 
        h3("Quartile plots"), uiOutput(ns("quartilesPlot")))
}

#' The server function of the boxplot module
#' 
#' This module produces displays of the quartiles of the values in the 
#' selected assay matrix. For low sample numbers (<= 20) the default is a 
#' boxplot produced using \code{ggplot2}. For higher sample numbers, the default is
#' a line-based alternative using \code{plotly}.
#' 
#' This function is not called directly, but rather via callModule() (see 
#' example).
#' 
#' @param input Input object
#' @param output Output object
#' @param session Session object
#' @param eselist ExploratorySummarizedExperimentList object containing
#'   ExploratorySummarizedExperiment objects
#'   
#' @keywords shiny
#'   
#' @examples
#' callModule(boxplot, 'boxplot', eselist)
#' 
#' # Almost certainly used via application creation
#' 
#' data(zhangneurons)
#' app <- prepareApp('boxplot', zhangneurons)
#' shiny::shinyApp(ui = app$ui, server = app$server)

boxplot <- function(input, output, session, eselist) {
    
    # Get the expression matrix - no need for a gene selection
    
    unpack.list(callModule(selectmatrix, "sampleBoxplot", eselist, select_genes = FALSE))
    unpack.list(callModule(groupby, "boxplot", eselist = eselist, group_label = "Color by", selectColData = selectColData))
    
    # Render the plot
    
    output$quartilesPlot <- renderUI({
        ns <- session$ns
        if (input$plotType == "boxes") {
            plotOutput(ns("sampleBoxplot"))
        } else {
            plotlyOutput(ns("quartilesPlotly"), height = "600px")
        }
    })
    
    output$quartilesPlotly <- renderPlotly({
        plotly_quartiles(selectMatrix(), getExperiment(), getAssayMeasure(), whisker_distance = input$whiskerDistance)
    })
    
    output$sampleBoxplot <- renderPlot({
        withProgress(message = "Making sample boxplot", value = 0, {
            ggplot_boxplot(selectMatrix(), selectColData(), getGroupby(), expressiontype = getAssayMeasure(), whisker_distance = input$whiskerDistance, palette = getPalette())
        })
    }, height = 600)
    
    # Provide the plot for download
    
    plotSampleBoxplot <- reactive({
        ggplot_boxplot(selectMatrix(), selectColData(), colorBy())
    })
    
    # Call to plotdownload module
    
    callModule(plotdownload, "boxplot", makePlot = plotSampleBoxplot, filename = "boxplot.png", plotHeight = 600, plotWidth = 800)
}

#' Make a boxplot with coloring by experimental variable
#' 
#' A simple function using \code{ggplot2} to make a sample boxplot
#'
#' @param plotmatrix Expression/ other data matrix
#' @param experiment Annotation for the columns of plotmatrix
#' @param colorby Column name in \code{experiment} specifying how boxes should be colored
#' @param palette Palette of colors, one for each unique value derived from 
#' \code{colorby}.
#' @param expressiontype Expression type for use in y axis label
#' @param whisker_distance Passed to \code{\link[ggplot2]{geom_boxplot}} as 
#' \code{coef}, controlling the length of the whiskers. See documentation of 
#' that function for more info (default: 1.5).
#'
#' @return output A \code{ggplot} output
#'
#' @keywords keywords
#'
#' @import ggplot2
#' @export
#' 
#' @examples
#' data(airway, package = 'airway')
#' ggplot_boxplot(assays(airway)[[1]], data.frame(colData(airway)), colorby = 'dex')

ggplot_boxplot <- function(plotmatrix, experiment, colorby = NULL, palette = NULL, expressiontype = "expression", whisker_distance = 1.5) {
    
    # If color grouping is specified, sort by the coloring variable so the groups will be plotted together
    
    if (!is.null(colorby)) {
        colnames(experiment)[colnames(experiment) == colorby] <- prettifyVariablename(colorby)
        colorby <- prettifyVariablename(colorby)
        
        experiment[[colorby]] <- na.replace(experiment[[colorby]], "N/A")
        
        # Group samples by the coloring variable while maintaining ordering as much as possible
        
        experiment <- experiment[order(factor(experiment[[colorby]], levels = unique(experiment[[colorby]]))), , drop = FALSE]
        plotmatrix <- plotmatrix[, rownames(experiment)]
    }
    
    # Reshape the data for ggplot2
    
    plotdata <- ggplotify(as.matrix(plotmatrix), experiment, colorby)
    
    # Make sure name is a factor to 1) stop ggplot re-ordering the axis and 2) stop it interpreting it as numeric
    
    plotdata$name <- factor(plotdata$name, levels = unique(plotdata$name))
    
    if (!is.null(colorby)) {
        p <- ggplot(plotdata, aes(name, log2_count, fill = colorby)) + geom_boxplot(coef = whisker_distance) + scale_fill_manual(name = colorby, values = palette) + 
            guides(fill = guide_legend(nrow = ceiling(length(unique(experiment[[colorby]]))/2)))
    } else {
        p <- ggplot(plotdata, aes(name, log2_count)) + geom_boxplot()
    }
    
    p <- p + theme_bw() + theme(axis.text.x = element_text(angle = 90, hjust = 1, size = rel(1.5)), axis.title.x = element_blank(), legend.position = "bottom", 
        axis.text.y = element_text(size = rel(1.5)), legend.text = element_text(size = rel(1.2)), title = element_text(size = rel(1.3))) + ylab(splitStringToFixedwidthLines(paste0("log2(", 
        expressiontype, ")"), 15))
    
    print(p)
}

#' Make a boxplot with coloring by experimental variable
#' 
#' A simple function using \code{plotly} to make a sample boxplot.
#' NOT CURRENTLY USED DUE TO RESOURCE REQUIREMENTS ON LARGE MATRICES
#'
#' @param plotmatrix Expression/ other data matrix
#' @param experiment Annotation for the columns of plotmatrix
#' @param colorby Column name in \code{experiment} specifying how boxes should be colored
#' @param expressiontype Expression type for use in y axis label
#'
#' @return output A \code{plotly} output
#'
#' @keywords keywords

plotly_boxplot <- function(matrix, experiment, colorby, expressiontype = "expression") {
    
    plotdata <- ggplotify(as.matrix(matrix), experiment, colorby)
    plot_ly(plotdata, type = "box", y = log2_count, x = name, color = colorby, evaluate = TRUE) %>% layout(yaxis = list(title = expressiontype), xaxis = list(title = NULL), 
        evaluate = TRUE) %>% config(showLink = TRUE)
}

#' Make a line-based alternative to boxplots
#' 
#' Box-plots become unmanagable with large numbers of samples. This function
#' plots lines at the median, quartiles, and whiskers, plotting points for 
#' outliers beyond that
#'
#' @param matrix 
#' @param ese ExploratorySummarizedExperiment
#' @param expressiontype Y axis label
#' @param whisker_distance IQR multiplier for whiskers, and beyond which to 
#' show outliers (see \code{coef} in \code{\link[ggplot2]{geom_boxplot}})
#'
#' @export
#' @examples 
#' data(airway, package = 'airway')
#' plotly_quartiles(assays(airway)[[1]], as(airway, 'ExploratorySummarizedExperiment'))

plotly_quartiles <- function(matrix, ese, expressiontype = "expression", whisker_distance = 1.5) {
    
    matrix <- log2(matrix + 1)
    
    quantiles <- apply(matrix, 2, quantile, na.rm = TRUE)
    samples <- structure(colnames(matrix), names = colnames(matrix))
    iqrs <- lapply(samples, function(x) {
        quantiles["75%", x] - quantiles["25%", x]
    })
    
    outliers <- lapply(samples, function(x) {
        y <- matrix[, x]
        ol <- y[which(y > quantiles["75%", x] + iqrs[[x]] * whisker_distance | y < quantiles["25%", x] - iqrs[[x]] * whisker_distance)]
        if (length(ol) > 0) {
            data.frame(x = x, y = ol, label = idToLabel(names(ol), ese), stringsAsFactors = FALSE)
        } else {
            NULL
        }
    })
    outliers <- do.call(rbind, outliers[!unlist(lapply(outliers, is.null))])
    
    # These lines to force plotly to use and display sample IDs as strings. For some reason character strings of numeric things get converted back
    
    # The plotting business
    
    plot_ly(data.frame(quantiles), mode = "markers") %>% add_trace(x = outliers$x, y = outliers$y, name = "outliers", marker = list(color = "black"), hoverinfo = "text", 
        text = outliers$label, type = "scatter") %>% add_lines(x = samples, y = quantiles["75%", ] + ((quantiles["75%", ] - quantiles["25%", ]) * whisker_distance), 
        line = list(width = 1, color = "grey", dash = "dash"), name = paste0("75%<br />+ (IQR * ", whisker_distance, ")")) %>% add_lines(x = samples, y = quantiles["75%", 
        samples], line = list(dash = "dash", color = "black"), name = "75%") %>% add_lines(x = samples, y = quantiles["50%", samples], line = list(dash = "solid", 
        color = "black"), name = "median") %>% add_lines(x = samples, y = quantiles["25%", samples], line = list(dash = "longdash", color = "black"), name = "25%") %>% 
        add_lines(x = samples, y = quantiles["25%", ] - ((quantiles["75%", ] - quantiles["25%", ]) * whisker_distance), line = list(width = 1, color = "grey", 
            dash = "longdash"), name = paste0("25%<br />- (IQR * ", whisker_distance, ")")) %>% layout(xaxis = list(title = NULL, categoryarray = samples, 
        categoryorder = "array"), yaxis = list(title = paste0("log2(", expressiontype, ")")), margin = list(b = 150), hovermode = "closest", title = NULL)
    
} 
