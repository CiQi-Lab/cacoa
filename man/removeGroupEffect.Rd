% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/coda.R, R/coda_balances.R
\name{removeGroupEffect}
\alias{removeGroupEffect}
\title{Remove the strongest group effect from balances}
\usage{
removeGroupEffect(d.used, d.groups, thresh.pc.var = 0.95)

removeGroupEffect(d.used, d.groups, thresh.pc.var = 0.95)
}
\arguments{
\item{d.used}{Currect values of balances}

\item{d.groups}{if provided then resampling controls presence of both groups in a new dataset}

\item{thresh.pc.var}{percentage of variance which should be characterised by PSc}

\item{n.seed}{Random seed}
}
\value{
Balances without group effect

Balances without group effect
}
\description{
Remove the strongest group effect from balances

Remove the strongest group effect from balances
}
\keyword{internal}
