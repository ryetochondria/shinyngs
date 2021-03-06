% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/gene.R
\name{geneModelPlot}
\alias{geneModelPlot}
\title{Make a gene model plot for a chromosomal location}
\usage{
geneModelPlot(ensembl_species, chromosome, start, end)
}
\arguments{
\item{ensembl_species}{Ensembl species definition like 'mmuscululus'}

\item{chromosome}{Chromosome number}

\item{start}{Chromosome start coordinate}

\item{end}{Chromosome end coordinate}
}
\description{
Uses the Gviz module to show transcripts and exon locations for a given gene
id.
}
