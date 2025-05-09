% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/de_function.R
\name{normalizePseudoBulkMatrix}
\alias{normalizePseudoBulkMatrix}
\title{Normalize pseudo-bulk matrix}
\usage{
normalizePseudoBulkMatrix(
  cm,
  meta = NULL,
  design.formula = NULL,
  type = "totcount"
)
}
\arguments{
\item{cm}{count matrix}

\item{meta}{(default=NULL)}

\item{design.formula}{(default=NULL)}

\item{type}{(default="totcount")}
}
\value{
normalized count matrix
}
\description{
Normalize pseudo-bulk matrix
}
\keyword{internal}
