#' @import sccore
NULL

#' Validate parameters per cell type
#'
#' @param raw.mats List of raw count matrices
#' @param cell.groups Named clustering/annotation factor with cell names
#' @param sample.groups Named factor with cell names indicating condition/sample, e.g., ctrl/disease
#' @param ref.level Reference cluster level in 'sample.groups', e.g., ctrl, healthy, wt
#' @keywords internal
validateDEPerCellTypeParams <- function(raw.mats, cell.groups, sample.groups, ref.level) {
  checkPackageInstalled("DESeq2", bioc=TRUE)

  if (is.null(cell.groups)) stop('"cell.groups" must be specified')
  if (is.null(sample.groups)) stop('"sample.groups" must be specified')
  if (class(sample.groups) != "list") stop('"sample.groups" must be a list')
  if (length(sample.groups) != 2) stop('"sample.groups" must be of length 2')
  if (!all(unlist(lapply(sample.groups, function(x) class(x) == "character")))){
    stop('"sample.groups" must be a list of character vectors')
  }

  if (!all(unlist(lapply(sample.groups, function(x) length(x) > 0)))){
    stop('"sample.groups" entries must be on length greater or equal to 1')
  }

  if (!all(unlist(lapply(sample.groups, function(x) all(x %in% names(raw.mats)))))){
    stop('"sample.groups" entries must be names of samples in the raw.mats')
  }

  if (is.null(ref.level)) stop('"ref.level" is not defined')
  ## todo: check samplegrousp are named
  if (is.null(names(sample.groups))) stop('"sample.groups" must be named')
  if (class(cell.groups) != "factor") stop('"cell.groups" must be a factor')
}

#' Subset matrices with common genes
#' @param cms List with count matrices
#' @param sample.groups (default=NULL)
#' @return list with count matrices with common genes
#' @keywords internal
subsetMatricesWithCommonGenes <- function(cms, sample.groups=NULL) {
  if (!is.null(sample.groups)) cms <- cms[unlist(sample.groups)]
  common.genes <- do.call(intersect, lapply(cms, colnames))
  cms %<>% lapply(function(m) m[, common.genes, drop=FALSE])
  return(cms)
}

#' Split strings and extract nth element
#' @description Function building on base::strsplit to extract nth element of a character string after splitting
#' 
#' @param x input character vector
#' @param split character vector containing a regular expression for splitting
#' @param n element to extract
#' @param fixed passed to strsplit
#' @keywords internal
strpart <- function(x, split, n, fixed = FALSE) {
  as.character(x) %>% strsplit(split, fixed=fixed) %>% sapply("[", n)
}

#' Add Z scores to DE results
#'
#' @param df Data.frame with the columns "pval", "padj" and "log2FoldChange"
#' @return Updated data.frame with Z scores
#' @examples 
#' \dontrun{
#' df_adj <- addZScores(df)
#' }
#' 
#' @export
addZScores <- function(df) {
  df$Z <- -qnorm(df$pval/2)
  df$Z[is.na(df$Z)] <- 0
  df$Za <- -qnorm(df$padj/2)
  df$Za[is.na(df$Za)] <- 0
  df$Z <- df$Z * sign(df$log2FoldChange)
  df$Za <- df$Za * sign(df$log2FoldChange)

  return(df)
}

#' Prepare samples for DE analysis
#' @param sample.groups named list containing sample names
#' @param resampling.method one of "loo" (leave-one-out, remove one sample per iteration), "bootstrap", "fix.cells" (fixed number of cells per subsample), or "fix.samples" (fixed number of samples per iteration)
#' @param n.resamplings number of iterations (default=30)
#' @keywords internal
prepareSamplesForDE <- function(sample.groups, resampling.method=c('loo', 'bootstrap', 'fix.cells', 'fix.samples'),
                                n.resamplings=30) {
  resampling.method <- match.arg(resampling.method)

  if (resampling.method == 'loo') {
    samples <- unlist(sample.groups) %>% sn() %>% lapply(function(n) lapply(sample.groups, setdiff, n))
  } else if (resampling.method == 'bootstrap') {
    # TODO: Do we ever use bootstrap? It seems that including the same sample many times
    # reduces variation and skews the analysis
    samples <- (1:n.resamplings) %>% setNames(paste0('bootstrap.', .)) %>%
      lapply(function(i) lapply(sample.groups, function(x) sample(x, length(x), replace=TRUE)))
  } else { # 'fix.cells' or 'fix.samples'
    samples <- (1:n.resamplings) %>% setNames(., paste0('fix.', .)) %>% lapply(function(i) sample.groups)
  }

  return(samples)
}

#' Differential expression using different methods (DESeq2, edgeR, wilcoxon, ttest) with various covariates
#'
#' @param raw.mats list of counts matrices; column for gene and row for cell
#' @param cell.groups factor specifying cell types (default=NULL)
#' @param s.groups list of two character vector specifying the app groups to compare (default=NULL)
#' @param ref.level reference level in 'sample.groups', e.g., ctrl, healthy, wt (default=NULL)
#' @param target.level target level in 'sample.groups' (default=NULL)
#' @param common.genes boolean Only investigate common genes across cell groups (default=FALSE)
#' @param cooks.cutoff boolean cooksCutoff for DESeq2 (default=FALSE)
#' @param min.cell.count numeric Minimum cell count (default=10)
#' @param max.cell.count numeric Maximum cell count (default=Inf). If Inf, there is no limit set.
#' @param fix.n.samples Number of samples to fix (default=NULL). If greater the the length of the s.groups, an error is thrown.
#' @param verbose boolean Whether to output verbose messages (default=TRUE)
#' @param independent.filtering boolean independentFiltering for DESeq2 (default=FALSE)
#' @param n.cores numeric Number of cores (default=1)
#' @param return.matrix Return merged matrix of results (default=TRUE)
#' @param meta.info dataframe with possible covariates; for example, sex or age
#' @param test DE method: DESeq2, edgeR, wilcoxon, ttest
#' @param gene.filter matrix/boolean Genes to omit (rows) per cluster (cols) (default=NULL)
#' @return differential expression for each cell type
#'
#' @export
estimateDEPerCellTypeInner <- function(raw.mats, cell.groups=NULL, s.groups=NULL, ref.level=NULL, target.level=NULL,
                                       common.genes=FALSE, cooks.cutoff=FALSE, min.cell.count=10, max.cell.count=Inf,
                                       independent.filtering=TRUE, n.cores=4, return.matrix=TRUE, fix.n.samples=NULL,
                                       verbose=TRUE, test='Wald', meta.info=NULL, gene.filter=NULL) {
  # Validate input
  validateDEPerCellTypeParams(raw.mats, cell.groups, s.groups, ref.level)
  tmp <- tolower(strsplit(test, split='\\.')[[1]])
  test <- tmp[1]
  test.type <- ifelse(is.na(tmp[2]), '', tmp[2])

  # Filter data and convert to the right format
  if (verbose) message("Preparing matrices for DE")
  if (common.genes) {
    raw.mats %<>% subsetMatricesWithCommonGenes(s.groups)
  } else {
    gene.union <- lapply(raw.mats, colnames) %>% Reduce(union, .)
    raw.mats %<>% lapply(sccore::extendMatrix, gene.union)
  }

  cm.bulk.per.samp <- raw.mats[unlist(s.groups)] %>% # Only consider samples in s.groups
    lapply(collapseCellsByType, groups=cell.groups, min.cell.count=min.cell.count, max.cell.count=max.cell.count) %>%
    .[sapply(., nrow) > 0] # Remove empty samples due to min.cell.count

  cm.bulk.per.type <- levels(cell.groups) %>% sn() %>% lapply(function(cg) {
    tcms <- cm.bulk.per.samp %>%
      lapply(function(cm) if (cg %in% rownames(cm)) cm[cg, , drop=FALSE] else NULL) %>%
      .[!sapply(., is.null)]
    if (length(tcms) == 0) return(NULL)

    tcms %>% {set_rownames(do.call(rbind, .), names(.))} %>% `mode<-`('integer') %>%
      .[,colSums(.) > 0,drop=FALSE]
  }) %>% .[sapply(., length) > 0] %>% lapply(t)

  ## Adjust s.groups
  passed.samples <- names(cm.bulk.per.samp)
  if (verbose && (length(passed.samples) != length(unlist(s.groups))))
    warning("Excluded ", length(unlist(s.groups)) - length(passed.samples), " sample(s) due to 'min.cell.count'.")

  s.groups %<>% lapply(intersect, passed.samples)

  # For every cell type get differential expression results
  if (verbose) message("Estimating DE per cell type")
  de.res <- names(cm.bulk.per.type) %>% sn()%>% plapply(function(l) {
    cm <- cm.bulk.per.type[[l]]
    if (!is.null(gene.filter)) {
      gene.to.remain <- gene.filter %>% {rownames(.)[.[,l]]} %>% intersect(rownames(cm))
      cm <- cm[gene.to.remain,,drop=FALSE]
    }

    cur.s.groups <- lapply(s.groups, intersect, colnames(cm))
    if (!is.null(fix.n.samples)) {
      if (min(sapply(s.groups, length)) < fix.n.samples) {
        warning("The cluster does not have enough samples")
        return(NULL)
      }
      cur.s.groups %<>% lapply(sample, fix.n.samples)
      cm <- cm[, unlist(cur.s.groups), drop=FALSE]
    }

    ## Generate metadata
    meta.groups <- colnames(cm) %>% lapply(function(y) {
      names(cur.s.groups)[sapply(cur.s.groups, function(x) any(x %in% y))]
    }) %>% unlist() %>% as.factor()

    if (length(levels(meta.groups)) < 2) {
      warning("The cluster is not present in both conditions")
      return(NULL)
    }

    # Each group should be presented in at least two samples
    n.samples <- sapply(levels(meta.groups), function(s) sum(meta.groups == s))
    if(min(n.samples) == 1){
      warning("Each group should be presented in at least two samples")
      return(NULL)
    }

    if (!ref.level %in% levels(meta.groups)) {
      warning("The reference level is absent in this comparison")
      return(NULL)
    }

    meta <- data.frame(sample.id=colnames(cm), group=relevel(meta.groups, ref=ref.level))

    ## External covariates
    if (is.null(meta.info)) {
      design.formula <- as.formula('~ group')
    } else {
      meta %<>% cbind(meta.info[meta$sample.id, , drop=FALSE])
      meta <- filterDEMetadata(meta)

      if(is.null(meta)){
        warning('Covariates are not independent')
        return(NULL)
      }

      if(!('group' %in% colnames(meta))) {
        warning('All samples of the same group')
        return(NULL)
      }

      design.formula <- c(colnames(meta)[-c(1,2)], 'group') %>%
        paste(collapse=' + ') %>% {paste('~', .)} %>% as.formula()
      message(design.formula)
    }

    if (test %in% c('wilcoxon', 't-test')) {
      cm <- normalizePseudoBulkMatrix(cm, meta=meta, design.formula=design.formula, type=test.type)
      res <- estimateDEForTypePairwiseStat(cm, meta=meta, target.level=target.level, test=test)
    } else if (test == 'deseq2') {
      res <- estimateDEForTypeDESeq(
        cm, meta=meta, design.formula=design.formula, ref.level=ref.level, target.level=target.level,
        test.type=test.type, cooksCutoff=cooks.cutoff, independentFiltering=independent.filtering
      )
    } else if (test == 'edger') {
      res <- estimateDEForTypeEdgeR(cm, meta=meta, design.formula=design.formula)
    } else if (test == 'limma-voom') {
      res <- estimateDEForTypeLimma(cm, meta=meta, design.formula=design.formula, target.level=target.level)
    }

    res$Gene <- rownames(res)

    if (!is.na(res[[1]][1])) {
      res <- addZScores(res) %>% .[order(.$pvalue, decreasing=FALSE),]
    }

    if (return.matrix)
      return(list(res = res, cm = cm, meta=meta))

    return(res)
  }, n.cores=n.cores, progress=verbose, mc.preschedule=TRUE, mc.allow.recursive=TRUE)  %>%
    .[!sapply(., is.null)]

  if (verbose) {
    dif <- setdiff(levels(cell.groups), names(de.res))
    if (length(dif) > 0) {
      message("DEs not calculated for ", length(dif), " cell group(s): ", paste(dif, collapse=', '))
    }
  }

  return(de.res)
}

#' Filter DE metadata
#' @param meta data frame containing metadata in columns
#' @return cleaned data frame with metadata
#' @keywords internal
filterDEMetadata <- function(meta) {
  # Remove unique columns
  i.m.remain <- c()
  for(i.m in 1:ncol(meta)){
    if(length(unique(meta[, i.m])) != 1) i.m.remain <- c(i.m.remain, i.m)
  }
  meta <- meta[, i.m.remain, drop=F]
  if(ncol(meta) == 1) return(meta)
  # The same columns
  for(i in 2:ncol(meta)){
    for(j in i:ncol(meta)){
      if(i == j) next
      if((nrow(unique(meta[,c(i, j)])) == length(unique(meta[,i]))))
        return(NULL)
    }
  }
  return(meta)
}

#' Normalize pseudo-bulk matrix
#' @param cm count matrix
#' @param meta (default=NULL)
#' @param design.formula (default=NULL)
#' @param type (default="totcount")
#' @return normalized count matrix
#' @keywords internal
# Requires availability test for DESeq2 or edgeR
normalizePseudoBulkMatrix <- function(cm, meta=NULL, design.formula=NULL, type='totcount') {
  if (type == 'deseq2') {
    cnts.norm <- DESeq2::DESeqDataSetFromMatrix(cm, meta, design=design.formula)  %>%
      DESeq2::estimateSizeFactors()  %>% DESeq2::counts(normalized=TRUE)
  } else if (type == 'edger') {
    cnts.norm <- edgeR::DGEList(counts=cm) %>% edgeR::calcNormFactors() %>% edgeR::cpm()
  } else if (type == 'totcount') {
    # the default should be normalization by the number of molecules!
    cnts.norm <- prop.table(cm, 2) # Should it be multiplied by median(colSums(cm)) ?
  }

  return(cnts.norm)
}

#' Estimate pair-wise DEGs
#' @param cm.norm normalized count matrix
#' @param meta data frame with meta data
#' @param target.level target level, e.g., disease group
#' @param test type of test, either "wilcoxon" or "t-test"
#' @return data frame containing DEGs using a pair-wise test
#' @keywords internal
# Requires availability test for "scran"
estimateDEForTypePairwiseStat <- function(cm.norm, meta, target.level, test) {
  if (test == 'wilcoxon') {
    res <- scran::pairwiseWilcox(cm.norm, groups = meta$group)$statistics[[1]] %>%
      data.frame() %>% setNames(c("AUC", "pvalue", "padj"))
  } else if (test == 't-test') {
    res <- scran::pairwiseTTests(cm.norm, groups = meta$group)$statistics[[1]] %>%
      data.frame() %>% setNames(c("AUC", "pvalue", "padj"))
  }

  # TODO: log2(x + 1) does not work for total-count normalization
  res$log2FoldChange <- log2(cm.norm + 1) %>% apply(1, function(x) {
    mean(x[meta$group == target.level]) - mean(x[meta$group != target.level])})

  return(res)
}

#' estimate DE using DESeq2
#' 
#' @param cm count matrix
#' @param meta data frame containing meta data
#' @param design.formula design formula according to 
#' @param ref.level reference level, e.g. controls
#' @param target.level target level, e.g. disease
#' @param test.type test type incorporated in DESeq2, either "Wald" or "LRT"
#' @param ... additional parameters forwarded to DESeq2
#' 
#' @keywords internal
estimateDEForTypeDESeq <- function(cm, meta, design.formula, ref.level, target.level, test.type, ...) {
  res <- DESeq2::DESeqDataSetFromMatrix(cm, meta, design=design.formula)
  if (test.type == 'wald') {
      res %<>% DESeq2::DESeq(quiet=TRUE, test='Wald')
  } else {
    res %<>% DESeq2::DESeq(quiet=TRUE, test='LRT', reduced = ~ 1)
  }

  res %<>% DESeq2::results(contrast=c('group', target.level, ref.level), ...) %>% as.data.frame()

  res$padj[is.na(res$padj)] <- 1

  return(res)
}

#' Estimate DE using edgeR
#' 
#' @param cm count matrix
#' @param meta data frame containing metadata
#' @param design.formula design formula according to 
#' 
#' @keywords internal
estimateDEForTypeEdgeR <- function(cm, meta, design.formula) {
  design <- model.matrix(design.formula, meta)

  qlf <- edgeR::DGEList(cm, group = meta$group) %>%
    edgeR::calcNormFactors() %>%
    edgeR::estimateDisp(design = design) %>%
    edgeR::glmQLFit(design = design) %>%
    edgeR::glmQLFTest(coef=ncol(design))

  res <- qlf$table %>% .[order(.$PValue),] %>% set_colnames(c("log2FoldChange", "logCPM", "stat", "pvalue"))
  res$padj <- p.adjust(res$pvalue, method="BH")

  return(res)
}

#' Estimate DE using limma
#' 
#' @param cm count matrix
#' @param meta data frame containing metadata
#' @param design.formula design formula according to 
#' @param target.level target level, e.g. disease
#' @keywords internal
estimateDEForTypeLimma <- function(cm, meta, design.formula, target.level) {
  mm <- model.matrix(design.formula, meta)
  fit <- limma::voom(cm, mm, plot = FALSE) %>% limma::lmFit(mm)

  contr <- limma::makeContrasts(paste0('group', target.level), levels=colnames(coef(fit)))
  res <- limma::contrasts.fit(fit, contr) %>% limma::eBayes() %>% limma::topTable(sort.by="P", n=Inf) %>%
    set_colnames(c('log2FoldChange', 'AveExpr', 'stat', 'pvalue', 'padj', 'B'))

  return(res)
}

#' Summarize DE Resampling Results
#'
#' @param de.list list with DE results. Data frame with DE results are found in the first element
#' @param var.to.sort Variable to calculate ranks (default="pvalue")
#' 
#' @keywords internal
summarizeDEResamplingResults <- function(de.list, var.to.sort='pvalue') {
  de.res <- de.list[[1]]
  for (cell.type in names(de.res)) {
    genes.init <- genes.common <- rownames(de.res[[cell.type]]$res)
    mx.stat <- matrix(nrow = length(genes.common), ncol = 0, dimnames = list(genes.common,c()))
    for (i in 2:length(de.list)) {
      if (!(cell.type %in% names(de.list[[i]]))) next
      genes.common <- intersect(genes.common, rownames(de.list[[i]][[cell.type]]))
      mx.stat <- cbind(mx.stat[genes.common,,drop=FALSE],
                       de.list[[i]][[cell.type]][genes.common, var.to.sort,drop=FALSE])
    }

    if (ncol(mx.stat) == 0) {
      warning("Cell type ", cell.type, " was not present in any subsamples")
      next
    }

    mx.stat <- apply(mx.stat, 2, rank)
    stab.mean.rank <- rowMeans(mx.stat) # stab - for stability
    stab.median.rank <- apply(mx.stat, 1, median)
    stab.var.rank <- apply(mx.stat, 1, var)

    de.res[[cell.type]]$res$stab.median.rank <- stab.median.rank[genes.init]
    de.res[[cell.type]]$res$stab.mean.rank <- stab.mean.rank[genes.init]
    de.res[[cell.type]]$res$stab.var.rank <- stab.var.rank[genes.init]

    # Save subsamples
    de.res[[cell.type]]$subsamples <- lapply(de.list[2:length(de.list)], `[[`, cell.type)
  }

  return(de.res)
}

#' Append statistics to DE results
#' 
#' @param de.list list with DE results
#' @param expr.frac.per.type 
#' 
#' @keywords internal
appendStatisticsToDE <- function(de.list, expr.frac.per.type) {
  for (n in names(de.list)) {
    de.list[[n]]$res %<>%
      mutate(CellFrac=expr.frac.per.type[Gene, n], SampleFrac=Matrix::rowMeans(de.list[[n]]$cm > 0)[Gene]) %>%
      as.data.frame(stringsAsFactors=FALSE) %>% set_rownames(.$Gene)
  }

  return(de.list)
}

#' get expression fraction per cell group
#' 
#' @param cm sparse count matrix 
#' @param cell.groups factor containing cell groups with cell names as names
#' 
#' @keywords internal
getExpressionFractionPerGroup <- function(cm, cell.groups) {
  cm@x <- as.numeric(cm@x > 1e-10)
  fracs <- collapseCellsByType(cm, cell.groups, min.cell.count=0) %>%
    {. / as.vector(table(cell.groups)[rownames(.)])} %>% Matrix::t()
  return(fracs)
}
