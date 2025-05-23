% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/ontology.R
\name{getDEEntrezIdsSplitted}
\alias{getDEEntrezIdsSplitted}
\title{Get DE ENTREZ IDs}
\usage{
getDEEntrezIdsSplitted(de.raw, org.db, p.adj = 1)
}
\arguments{
\item{de.raw}{List with differentially expressed genes per cell group}

\item{org.db}{Organism database, e.g., org.Hs.eg.db for human or org.Ms.eg.db for mouse. Input must be of class 'OrgDb'}

\item{p.adj}{Adj. P cutoff for filtering DE genes (default=0.05)}
}
\value{
A list containing DE ENSEMBL gene IDs, and filtered DE genes
}
\description{
Filter and prepare DE genes for ontology calculations
}
\keyword{internal}
