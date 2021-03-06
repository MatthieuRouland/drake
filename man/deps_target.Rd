% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/exec-dependencies.R
\name{deps_target}
\alias{deps_target}
\title{List the dependencies of a target}
\usage{
deps_target(target, config, character_only = FALSE)
}
\arguments{
\item{target}{A symbol denoting a target name, or if \code{character_only}
is TRUE, a character scalar denoting a target name.}

\item{config}{An output list from \code{\link[=drake_config]{drake_config()}}.}

\item{character_only}{Logical, whether to assume target is a character
string rather than a symbol.}
}
\value{
A data frame with the dependencies listed by type
(globals, files, etc).
}
\description{
Intended for debugging and checking your project.
The dependency structure of the components of your analysis
decides which targets are built and when.
}
\examples{
\dontrun{
isolate_example("Quarantine side effects.", {
load_mtcars_example() # Get the code with drake_example("mtcars").
config <- drake_config(my_plan)
deps_target("regression1_small", config = config)
})
}
}
\seealso{
\code{\link[=deps_code]{deps_code()}}, \code{\link[=deps_knitr]{deps_knitr()}}
}
