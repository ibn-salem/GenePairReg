#!/usr/bin/Rscript
#=======================================================================
#
#   Check the distribution of strand specific genes and pseudo genes
#   with respect to TADs.
# 
#=======================================================================

#-----------------------------------------------------------------------
# load some useful libraries
#-----------------------------------------------------------------------
require(stringr)        # for functions like paste0()
require(GenomicRanges)  # for GRanges objects
require(ggplot2)        # for nice plots
require(xtable)         # to directly output latex tables
require(RColorBrewer)   # for nice colors
require(BiocParallel)   # for parallel computing

#-----------------------------------------------------------------------
# Load parameters from external script
#-----------------------------------------------------------------------
# read parameter script location from command-line argument
#~ args <- commandArgs(trailingOnly = TRUE)
#~ PARAM_SCRIPT=args[1]
PARAM_SCRIPT="R/TAD_gene_distribution.param.v04.R"
source(PARAM_SCRIPT)

#-----------------------------------------------------------------------
# Options for parallel computation
#-----------------------------------------------------------------------
# use all available cores but generate random number streams on each worker
multicorParam <- MulticoreParam(RNGseed=RANDOM_SEED)   
# set options
register(multicorParam)  
# bpparam() # to print current options

# load costume scripts
source("R/functions.GRanges.R")
source("R/functions.plot.R")
source("R/parseHiC.R")

source("R/data.ensembl.R")

#=======================================================================
# parse input data
#=======================================================================

if (GENE_COORDINATE_CENTER){
    protCodingGR <- getCenterAsGR(genes, seqInfoRealChrom, colNames=c("hgnc_symbol"))
}else{
    protCodingGR <- getTssGRfromENSEMBLGenes(genes, seqInfoRealChrom, colNames=c("hgnc_symbol"))
}

# parse TAD data sets as list of GRanges
RaoTADs = lapply(RaoDomainFiles, parseDomainsRao, disjoin=FALSE, seqinfo=seqInfo)

# parse TADs form Dixon et al. 2012
DixonTADs <- lapply(DixonDomainFiles, import.bed, seqinfo=seqInfo)

#~ allTADs <- c(
#~     RaoTADs, 
#~     list(
#~         "GM12878_nonOverlapping"=RaoTADs[["Rao_GM12878"]][selfOverlap == 1],
#~         "Stable"=getConservedTADs(RaoTADs, n=4, fraction=.9)
#~     )
#~ )
rawTADs <- c(
    RaoTADs, 
    DixonTADs,
    list("Rao_stable"=getConservedTADs(RaoTADs, n=4, fraction=.9))
)

nonOvlpTADs <- lapply(rawTADs, filterForNonOverlapping)
names(nonOvlpTADs) <- paste0(names(nonOvlpTADs), "_nonOVLP")

# count number of genes within each TAD to get gene density:
genesPerTAD <- lapply(rawTADs, countOverlaps, protCodingGR)
sizePerTAD <- lapply(rawTADs, width)
genesPerMbPerTAD <- mapply(function(g,s) g/(s/10^6), genesPerTAD, sizePerTAD)

# filter for 75% quantile of gene density for each TAD data set
geneDenstyTHs <-  sapply(genesPerMbPerTAD, quantile, c(.25, .75))
geneDenseTADs <- mapply(function(gr, gd, th) gr[gd>=th], rawTADs, genesPerMbPerTAD, geneDenstyTHs[2])
geneSparseTADs <- mapply(function(gr, gd, th) gr[gd<th], rawTADs, genesPerMbPerTAD, geneDenstyTHs[1])

names(geneDenseTADs) <- paste0(names(rawTADs), "_gene_dense")
names(geneSparseTADs) <- paste0(names(rawTADs), "_gene_sparse")

allTADs <- c(rawTADs, nonOvlpTADs, geneDenseTADs, geneSparseTADs)

#~ # remove "Rao_" prefix from list names
#~ names(allTADs) <- gsub("Rao_", "", names(allTADs))

# write all TADs to BED files:
for (tadName in names(allTADs)){
    TAD = allTADs[[tadName]]
    export(sort(TAD), paste0(outPrefix, ".TAD_data.", tadName, ".bed"))
}

#-----------------------------------------------------------------------
# parse essential genes:
#-----------------------------------------------------------------------
OGEE <- read.table(OGEEdbFile, header=TRUE, comment.char="", sep="\t")
essentialIDs <- OGEE[OGEE$essential == "Y", "locus"]
geneIDX <- match(as.character(essentialIDs), names(protCodingGR))
essentialGenes = protCodingGR[geneIDX[!is.na(geneIDX)]]

geneIDXfull <- match(as.character(essentialIDs), names(genesGR))
essentialGenesFull = genesGR[geneIDXfull[!is.na(geneIDXfull)]]
#-----------------------------------------------------------------------
# parse pseudo genes as TSS or center coordinate
#-----------------------------------------------------------------------
parsePsgCoord <- function(inFile, useCenter=FALSE){
    
    d = read.table(inFile, header=TRUE)

    # build GRanges object
    wholeGeneGR <- GRanges(
        d$Chromosome,
        IRanges(d$Start, d$End),
        strand = d$Strand, 
        names = d$Pseudogene_id,
        d[,c("Biotype", "Parent_gene", "Parent_transcript", "Parent_name")],
        seqinfo=seqInfo
        )
        
    # if useCenter take the center point coordinate otherwise take only the start coordinate
    if(useCenter){
        gr <- resize(wholeGeneGR, 1, fix="center", ignore.strand=FALSE)
    }else{
        gr <- resize(wholeGeneGR, 1, fix="start", ignore.strand=FALSE)
    }
    
    return(gr)
}

# parse the pseudogenes
PsgList = lapply(PseudoGenesFiles, parsePsgCoord, useCenter=GENE_COORDINATE_CENTER)

#-----------------------------------------------------------------------
# parse pseudo genes as TSS or center coordinate
#-----------------------------------------------------------------------
parsePsg <- function(inFile){
    
    d <- read.table(inFile, header=TRUE)

    # build GRanges object
    gr <- wholeGeneGR <- GRanges(
        d$Chromosome,
        IRanges(d$Start, d$End),
        strand = d$Strand, 
        names = d$Pseudogene_id,
        d[,c("Biotype", "Parent_gene", "Parent_transcript", "Parent_name")],
        seqinfo=seqInfo
        )
    return(gr)
}
# parse the pseudogenes
PsgListFull = lapply(PseudoGenesFiles, parsePsg)

#-----------------------------------------------------------------------
# combine all types of genes
#-----------------------------------------------------------------------

# list of GRs of TSS of gene types of interest to be counted inside and outside of the TADs
#~ geneTypeTssList = c(
#~     list("protGenes"=protCodingGR), 
#~     lapply(c(list("lincRNA"=lincRNAsGR), PsgList), resize, width=1, fix="start")
#~     )
geneTypeTssList = c(
    list("essentialGenes"=essentialGenes, "protGenes"=protCodingGR), 
    lapply(
        list("Psg_non-TS"=c(PsgList[["Psg_proc_non-TS"]], PsgList[["Psg_dup_non-TS"]])), 
        resize, width=1, fix="start")
    )

geneTypeFullList = c(
    list(
    "essentialGenes"=essentialGenesFull, 
    "protGenes"=genesGR,
    "Psg_non-TS"=c(PsgListFull[["Psg_proc_non-TS"]], PsgListFull[["Psg_dup_non-TS"]]))
    )

geneTypeCoverage <- lapply(geneTypeFullList, function(gr){
    list(
        "+"=coverage(gr[strand(gr) == "+"], method="auto"),
        "-"=coverage(gr[strand(gr) == "-"], method="auto")
    )
})

geneTypeCenter <- lapply(geneTypeTssList, function(gr){
    list(
        "+"=coverage(gr[strand(gr) == "+"], method="auto"),
        "-"=coverage(gr[strand(gr) == "-"], method="auto")
    )
})


#-----------------------------------------------------------------------
# Transpose a list of n GRAnges with m equal sized bins into list of all the ith bin 
#-----------------------------------------------------------------------
transposeBinList <- function(TADbins, m=20, inParallel=TRUE){
    allBins = unlist(TADbins)
    n = length(allBins)
    bplapply(1:m, function(i) allBins[seq(i,n,m)])    
}   

fractionOfGenome <- function(gr, seqinfo=seqInfo){
    genomeLength = sum(as.numeric(seqlengths(seqInfo)))
    sum(as.numeric(width(reduce(gr, ignore.strand=TRUE)))) / genomeLength
}

#-----------------------------------------------------------------------
# Summary table of TAD data
#-----------------------------------------------------------------------

TADstats = round(data.frame(
    "n" = sapply(allTADs , length), 
    "mean_size" = sapply(sapply(allTADs, width), mean) / 10^3,
    "sd_size" = sapply(sapply(allTADs, width), sd) / 10^3, 
    "median_size" = sapply(sapply(allTADs, width), median) / 10^3, 
    "percent_genome" = sapply(allTADs, fractionOfGenome),
    "avg_genes" = sapply(allTADs, function(tadGR) mean(countOverlaps(tadGR, protCodingGR)))
    ), 2)
row.names(TADstats) = names(allTADs)

write.table(TADstats, paste0(outPrefix, ".TAD_statistics.csv"), sep="\t", quote=FALSE, col.names=NA)
print.xtable(xtable(TADstats), type="latex", file=paste0(outPrefix, ".TAD_statistics.tex"))

# write gene density threshold per TAD
write.table(cbind(geneDenstyTHs), paste0(outPrefix, ".TAD_geneDensity_TH.csv"), sep="\t", quote=FALSE, col.names=NA)

#-----------------------------------------------------------------------
# Summary table of genes
#-----------------------------------------------------------------------
RegStats = round(data.frame(
    "n" = sapply(geneTypeTssList, length), 
    "mean_size" = sapply(sapply(geneTypeFullList, width), mean) / 10^3,
    "sd_size" = sapply(sapply(geneTypeFullList, width), sd) / 10^3, 
    "median_size" = sapply(sapply(geneTypeFullList, width), median) / 10^3, 
    "percent_genome" = sapply(geneTypeFullList, fractionOfGenome)
    ), 2)
    
write.table(RegStats, paste0(outPrefix, ".geneTypeTssList_statistics.csv"), sep="\t", quote=FALSE, col.names=NA)

#-----------------------------------------------------------------------
# Save temporary parsed data as R image
#-----------------------------------------------------------------------
save.image(paste0(WORKIMAGE_FILE, ".parsing.tmp.Rdata"))

#-----------------------------------------------------------------------
# Calculate the coverage along TADs of strand separated gene types
#-----------------------------------------------------------------------
# iterate over bin numbers:
for (nBin in N_BIN_LIST){
    
    # nBin=40
    summaryDF = data.frame()
#~     summaryList = list()
        
    # Iterate over each set of TADs
#~     for (TADname in names(allTADs)) {
    for (TADname in c("Rao_GM12878", "Rao_GM12878_nonOVLP", "Rao_GM12878_gene_sparse", "Rao_GM12878_gene_dense")) {
        
        TAD = allTADs[[TADname]]
        
        # resize TADs by +-50% and divide them into equal sized bins
        TADreg = TAD
        ranges(TADreg) = IRanges(start(TAD) - .5 * width(TAD), end(TAD) + .5 * width(TAD))
        
        # drop TADs that extends out of the chromosome space
        withinChrom = width(TADreg) == width(IRanges::trim(TADreg))
        TADreg = TADreg[withinChrom]
        message(paste0("INFO: Keep ", sum(withinChrom), " of ", length(withinChrom), " TADs that have extended range within chromosomes."))
        
        # make nBin equal sized bins for each TAD
        TADbins <- tile(TADreg, n=nBin)
        seqinfo(TADbins) <- seqInfo
        
        # transpose the list to have always the i-th bin together
        TADbinsList = transposeBinList(TADbins, nBin, inParallel=TRUE)
        Sys.sleep(1) # hack to fix problems with bplapply on MOGON

        TADbinsSize = width(TADbinsList[[1]])

#~         # get bins arround TAD boundaries
#~         BoundaryBins = binsAroundTADboundaries(TAD, windowSize=WINDOW_SIZE, nbins=nBin)
#~         message("INFO: Finished calculation of bins.")
#~     
#~         # transform bin list to get each i-th bin together
#~         boundaryBinList = transposeBinList(BoundaryBins, nBin)
        
        # query the coverage vectors:
        for (GENETYPE in names(geneTypeCoverage)){
#~         for (GENETYPE in "protGenes"){
            
            
            for (STRAND in c("+", "-")){
#~                 STRAND="+"
                message(paste("INFO: Iterate", TADname, GENETYPE, STRAND))
                
                covVec <-geneTypeCoverage[[GENETYPE]][[STRAND]] 
                centerVec <- geneTypeCenter[[GENETYPE]][[STRAND]] 
                
                # compute coverage of TADs by taking the mean of coding bases in each bin
                sumCov <- bplapply(TADbinsList, function(tb) sum(covVec[tb]))
                Sys.sleep(1) # hack to fix problems with bplapply on MOGON
                
                sumCenter <- bplapply(TADbinsList, function(tb) sum(centerVec[tb]))
                Sys.sleep(1) # hack to fix problems with bplapply on MOGON

                perBp <- lapply(sumCov, function(cov) cov / TADbinsSize )
                perBpCenter <- lapply(sumCenter, function(cov) cov / TADbinsSize )

                # add to summaryDF
                avCov <- sapply(perBp, mean)
                sdCov <- sapply(perBp, sd)

                avCenter <- sapply(perBpCenter, mean)
                sdCenter <- sapply(perBpCenter, sd)
                
                summaryDF <- rbind(summaryDF, 
                    data.frame(
                        "avCov"=avCov, 
                        "sdCov"=sdCov,
                        "avCenter"=avCenter, 
                        "sdCenter"=sdCenter,
                        "tad"=rep(TADname, nBin),
                        "geneType"=rep(GENETYPE, nBin),
                        "strand"=rep(STRAND, nBin),
                        "bin"=1:nBin
                    )
                )

            }   # strand
        }   # gene_type 
        save(summaryDF, file=paste0(outPrefix, ".nBin_", nBin, "TAD_", TADname, ".summaryDF.Rdata"))

    } # tad 
    
    # save summaryDF
    save(summaryDF, file=paste0(outPrefix, ".nBin_", nBin, ".summaryDF.Rdata"))
#~     load(paste0(outPrefix, ".nBin_", nBin, ".summaryDF.Rdata"))
    
#~     names(summaryDF)[1:2] <- c("avCov", "sdCov") 
#~     summaryDF[,1] <- as.numeric(as.character(summaryDF[,1])) 
#~     summaryDF[,2] <- as.numeric(as.character(summaryDF[,2])) 

    xlabsTADs = rep("", nBin+1)
    names(xlabsTADs) = as.character(0:(nBin))
    xlabsTADs[seq(0,nBin, nBin/4)+1] = c("-50%", "start", "TAD", "end", "+50%")
    TADrect <- data.frame(xmin=nBin/4+1-.5, xmax=3*nBin/4+1-.5, ymin=-Inf, ymax=Inf)

    plotTADrect = geom_rect(data=TADrect, aes(xmin=xmin, xmax=xmax, ymin=ymin, ymax=ymax),color="grey20", alpha=0.10, inherit.aes = FALSE)
    plotXtickesTAD = scale_x_discrete(labels=xlabsTADs)
    
    # plot coverage along TAD.
    g <- ggplot(summaryDF, aes(x=bin, y=avCov, group=paste(geneType, strand), col=strand)) + geom_line() + geom_point(aes(shape=geneType)) +
#~     + geom_point(aes(shape=21), size=3, fill="white") + geom_point(aes(shape=strand), size=5) + scale_shape_identity() + 
#~         geom_errorbar(aes(ymin=avCov-sdCov, ymax=avCov+sdCov), width=.1) + 
        theme_bw() + scale_color_manual(values=c("+"="blue", "-"="red")) + 
        facet_grid(geneType~tad, scales="free_y") + 
        theme(legend.position="bottom") +ylab("Average covered bp") + 
        plotTADrect + plotXtickesTAD
    ggsave(filename=paste0(outPrefix, ".nBin_", nBin, ".summaryDF.geneType_cov_around_TAD.pdf"), w=14,h=7)        

    g <- ggplot(summaryDF, aes(x=bin, y=avCenter, group=paste(geneType, strand), col=strand)) + geom_line() + geom_point(aes(shape=geneType)) + 
#~         geom_errorbar(aes(ymin=avCov-sdCov, ymax=avCov+sdCov), width=.1) + 
        theme_bw() + scale_color_manual(values=c("+"="blue", "-"="red")) + 
        facet_grid(geneType~tad, scales="free_y") + 
        theme(legend.position="bottom") +ylab("Average Gene center positions") + 
        plotTADrect + plotXtickesTAD
    ggsave(filename=paste0(outPrefix, ".nBin_", nBin, ".summaryDF.geneType_CenterPos_around_TAD.pdf"), w=14,h=7)        

        
} # nBin



#-----------------------------------------------------------------------
# Counts the number of overlaps of qurey regions separated by + and - strand 
# in first and second half of  the target regions
# return summed counts in the form (firsthalf_+ firsthalf_- secondHalf_+ secondHalf-) for each region type in the input region list
#-----------------------------------------------------------------------
getStrandedCountsPerHalf <- function(TAD, geneTypeTssList){

    # convert regions into GRanges list separted for plus and minus strand
    grl <- GRangesList(lapply(geneTypeTssList, function(gr){
        mcols(gr) <- NULL
        return(gr)}))
    grlPos <- grl[strand(grl) == "+"]
    grlNeg <- grl[strand(grl) == "-"]
    
    # divide TAD in two halfs (bins)
    TADbins <- tile(TAD, 2)
    TADbinsList = transposeBinList(TADbins, 2)
    
    # count the number of regions separated by halfs of TADs and strand of gene
    counts <- as.vector(rbind(
        sapply(grlPos, function(gr) sum(countOverlaps(gr, TADbinsList[[1]])) ),
        sapply(grlNeg, function(gr) sum(countOverlaps(gr, TADbinsList[[1]])) ),
        sapply(grlPos, function(gr) sum(countOverlaps(gr, TADbinsList[[2]])) ),
        sapply(grlNeg, function(gr) sum(countOverlaps(gr, TADbinsList[[2]])) )
    ))
}

# get overlap counts per TAD half for + and - stranded genes
counts <- sapply(allTADs, getStrandedCountsPerHalf, geneTypeTssList)
#~ counts_nonOVLP <- sapply(allTADs_nonOVLP, getStrandedCountsPerHalf, geneTypeTssList)

# get number of overlapping genes per TAD type
nGenes <- apply(counts, 2, function(v){
    rep(tapply(v, (seq_along(v)-1) %/% 4, sum), each=4)
    })

# get the percent of counts
percents <- counts / nGenes * 100 

# get the total number of genes per type
nGenesTotal <- sapply(geneTypeTssList, length)

# construct some factor object to better handle the plotting
geneTypeFactor <- factor(names(geneTypeTssList), names(geneTypeTssList), labels=paste0(names(geneTypeTssList), "\nn = ", nGenesTotal))
TadFactor <- factor(names(rawTADs), names(rawTADs))
TadTypeFactor <- factor(c("Raw", "nonOVLP", "geneDense", "geneSparse"), c("Raw", "nonOVLP", "geneDense", "geneSparse"))

# get numbers of TADs, gnee types, bins, and strands
#~ nTAD <- length(allTADs)
nTAD <- length(TadFactor)
nTADtype <- length(TadTypeFactor)
nGeneType <- length(geneTypeTssList)
nBin <- 2
nStrand <- 2


# construct an data frame with all data for plotting with the ggplot framework
countDF <- data.frame(
    "overlaps"=as.vector(counts),
    "nGenes"=as.vector(nGenes),
    "percent"=as.vector(percents),
    "TADtype"=rep(TadTypeFactor, each=nTAD*nGeneType*nBin*nStrand),
    "TAD"=rep(rep(TadFactor, each=nGeneType*nBin*nStrand), nTADtype),
    "GeneType"=rep(rep(geneTypeFactor, each=nBin*nStrand), nTADtype*nTAD),
    "Half"=rep(rep(factor(c("1st", "2nd")), each=nStrand), nTADtype*nTAD*nGeneType),
    "Strand"=rep(factor(c("+", "-"), c("+", "-")), nTADtype*nTAD*nGeneType*nBin)
)

# get fisher test p-values and odds ratios:
# iterate over pairs of conditions:
combination <- sapply(TadTypeFactor, function(tadType){
    sapply(names(rawTADs), function(tad){
        sapply(geneTypeFactor, function(geneType){
            paste(tadType, tad, geneType, sep="|")
        })
    })
})

pVals <- sapply(TadTypeFactor, function(tadType){
    sapply(names(rawTADs), function(tad){
        sapply(geneTypeFactor, function(geneType){
            fisher.test(
                matrix(countDF[countDF$TADtype == tadType & countDF$GeneType == geneType & countDF$TAD==tad, "overlaps"], 2)
            )$p.value
        })
    })
})

ors <- sapply(TadTypeFactor, function(tadType){
    sapply(names(rawTADs), function(tad){
        sapply(geneTypeFactor, function(geneType){
            fisher.test(
                matrix(countDF[countDF$TADtype == tadType & countDF$GeneType == geneType & countDF$TAD==tad, "overlaps"], 2)
            )$estimate
        })
    })
})

yMax = max(countDF$percent)

# make data frame for plot annotations
annotDF <- data.frame(
    comb=as.vector(combination),
    pVals=as.vector(pVals),
    nGenes=as.vector(nGenes)[seq(nrow(nGenes)) %% 4 == 1],
    ors=as.vector(ors),
    percent=rep(yMax, nTADtype*nTAD*nGeneType),
    TADtype=rep(TadTypeFactor, each=nTAD*nGeneType),
    TAD=rep(rep(TadFactor, each=nGeneType), nTADtype),
    GeneType=rep(geneTypeFactor, nTADtype*nTAD),
    Half=rep(factor("1st", c("1st", "2nd")), nTADtype*nTAD*nGeneType),
    Strand=rep(factor("-", c("+", "-")), nTADtype*nTAD*nGeneType)
)

starsNotation = matrix(pValToStars(pVals, ""), nrow(pVals))

pdf(paste0(outPrefix, ".Genes_in_TAD_half.stranded.counts.barplot.pdf"), w=14, h=7)
    
    ggplot(countDF, aes(x=Half, y=overlaps, fill=Strand)) + geom_bar(position="dodge",stat="identity") +  
    facet_grid(TADtype*GeneType~TAD, scales="free_y") +
    theme_bw() + scale_fill_manual(values=COL_STRAND) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1), strip.text.y = element_text(angle=0)) +
    geom_text(aes(label=overlaps), position=position_dodge(width=1), hjust=+1, vjust=0.5, size=3, angle=90) +
    labs(y="Overlaps", x="TAD half")
dev.off()

pdf(paste0(outPrefix, ".Genes_in_TAD_half.stranded.percent.barplot.pdf"), w=14, h=7)
    
    ggplot(countDF, aes(x=Half, y=percent, fill=Strand)) + geom_bar(position="dodge",stat="identity") +  
    facet_grid(TADtype*GeneType~TAD) +
    theme_bw() + scale_fill_manual(values=COL_STRAND) + ylim(0, 1.4*yMax) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1), strip.text.y = element_text(angle=0)) +
    geom_text(aes(label=signif(percent, 3)), position=position_dodge(width=1), hjust=+1, vjust=0.5, size=3, angle=90) +
    geom_text(data=annotDF, aes(x=1.5, y=1.3*yMax, label=paste0("OR=", signif(ors, 2))), size=2.5 ) +
    geom_text(data=annotDF, aes(x=1.5, y=1.1*yMax, label=paste0("p=", signif(pVals, 2))), size=2.5) + 
    geom_text(data=annotDF, aes(x=1.5, y=.9*yMax, label=paste0("n=", nGenes)), size=2.5) + 
    labs(y="% overlaps", x="TAD half")
dev.off()

#=======================================================================
# now combine genes on positive strand in first bin with genes on negative strand in second bin
# and genes on negative strand in first bin with genes on positive stran in second bin.
#=======================================================================

sumFirstAndFourth <- function(v){
    s = v[which((seq_along(v)-1) %% 4 %in% c(0,3))]
    tapply(s, (seq_along(s)-1) %/% 2, sum)
}

sumSecondAndThird <- function(v){
    s = v[which((seq_along(v)-1) %% 4 %in% c(1,2))]
    tapply(s, (seq_along(s)-1) %/% 2, sum)
}

borderToCenter <- apply(counts, 2, sumFirstAndFourth)
centerToBorder <- apply(counts, 2, sumSecondAndThird)

# construct an data frame with all data for plotting with the ggplot framework
mergedCountDF <- data.frame(
    "overlaps"=c(rbind(c(borderToCenter), c(centerToBorder))),
    "nGenes"=as.vector(nGenes)[which((seq_along(nGenes)-1) %% 4 %in% 0:1)],
    "TADtype"=rep(TadTypeFactor, each=nTAD*nGeneType*nStrand),
    "TAD"=rep(rep(TadFactor, each=nGeneType*nStrand), nTADtype),
    "GeneType"=rep(rep(geneTypeFactor, each=nStrand), nTADtype*nTAD),
    "Direction"=rep(factor(c("borderToCenter", "centerToBorder")), nTADtype*nTAD*nGeneType)
)

yMaxPerGeneType = apply(
    rbind(apply(borderToCenter, 1, max), apply(centerToBorder, 1, max)),
    2, max)

yMaxPerTADypePerGenetype <- sapply(TadTypeFactor, function(TADtype){
    sapply(geneTypeFactor, function(geneType){
        max(mergedCountDF[mergedCountDF$TADtype==TADtype & mergedCountDF$GeneType == geneType, "overlaps"])
    })
})

ratios <- sapply(TadTypeFactor, function(TADtype){
    sapply(TadFactor, function(tad){
        sapply(geneTypeFactor, function(geneType){
            ols <- mergedCountDF[mergedCountDF$TADtype==TADtype & mergedCountDF$TAD==tad & mergedCountDF$GeneType == geneType, "overlaps"]
            ols[1] / ols[2]
        })
    })
})

yMax <- max(mergedCountDF$overlaps)

# make data frame for plot annotations
mergedAnnotDF <- data.frame(
    comb=as.vector(combination),
    pVals=as.vector(pVals),
    pValsLab=pValToStars(as.vector(pVals), ""),
    nGenes=as.vector(nGenes)[seq(nrow(nGenes)) %% 4 == 1],
    ors=as.vector(ors),
    ratios=as.vector(ratios),
    overlaps=as.vector(apply(yMaxPerTADypePerGenetype, 2, function(tadTypeMax) {rep(tadTypeMax, nTAD)})),
    yMaxPerGeneType=rep(yMaxPerGeneType, nTADtype*nTAD),
    TADtype=rep(TadTypeFactor, each=nTAD*nGeneType),
    TAD=rep(rep(TadFactor, each=nGeneType), nTADtype),
    GeneType=rep(geneTypeFactor, nTADtype*nTAD),
    Direction=rep(factor("borderToCenter", c("borderToCenter", "centerToBorder")), nTADtype*nTAD*nGeneType)
)

pdf(paste0(outPrefix, ".Genes_in_TAD_half.stranded.counts_merged.barplot.pdf"), w=14, h=7)
    
    ggplot(mergedCountDF, aes(x=TAD, y=overlaps, fill=Direction)) + geom_bar(position="dodge", stat="identity") +  
    facet_grid(GeneType~TADtype, scales="free_y") +
    theme_bw() + scale_fill_manual(values=COL_STRAND) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
    geom_text(aes(label=overlaps, y=0), position=position_dodge(width=1), hjust=-0.25, vjust=0.5, size=3, angle=90) +
    geom_text(data=mergedAnnotDF, aes(x=TAD, y=yMaxPerGeneType, label=pValsLab), size=3 ) +
#~     geom_text(data=mergedAnnotDF, aes(x=TAD, y=.95*yMaxPerGeneType, label=paste0("", signif(pVals, 2))), size=3 ) +
    geom_text(data=mergedAnnotDF, aes(x=TAD, y=.95*yMaxPerGeneType, label=paste0("", signif(ratios, 2))), size=3 ) +
    labs(y="Overlap counts", x="TAD data set")
dev.off()

# plot barplot for the ratio and p-value
pdf(paste0(outPrefix, ".Genes_in_TAD_half.stranded.merged_ratio.barplot.pdf"), 7, 7)
    ggplot(mergedAnnotDF, aes(x=GeneType, y=ratios, fill=GeneType)) + geom_bar(position="dodge", stat="identity") +  
    geom_hline(yintercept=1, col="red") +
    facet_grid(TADtype~TAD, scales="free_y") +
    theme_bw() + scale_fill_manual(values=COL_REGIONS) +
    theme(axis.text.x = element_blank(), strip.text.x = element_text(angle=90)) +
    geom_text(aes(label=signif(ratios,2), y=0), position=position_dodge(width=1), hjust=0, vjust=0.5, size=3, angle=90) +
#~     geom_text(data=mergedAnnotDF, aes(x=TAD, y=ratios, label=pValsLab), size=3 ) +
    labs(y="Ratio (5'/3')", x="TAD data set")
dev.off()

pdf(paste0(outPrefix, ".Genes_in_TAD_half.stranded.merged_log_ratio.barplot.pdf"), 7, 7)
    ggplot(mergedAnnotDF, aes(x=GeneType, y=log(ratios), fill=GeneType)) + geom_bar(position="dodge", stat="identity") +  
#~     geom_hline(yintercept=1, col="red") +
    facet_grid(TADtype~TAD, scales="free_y") +
    theme_bw() + scale_fill_manual(values=COL_REGIONS) +
    theme(axis.text.x = element_blank(), strip.text.x = element_text(angle=90)) +
    geom_text(aes(label=signif(log(ratios),2), y=0), position=position_dodge(width=1), hjust=0, vjust=0.5, size=3, angle=90) +
#~     geom_text(data=mergedAnnotDF, aes(x=TAD, y=ratios, label=pValsLab), size=3 ) +
    labs(y="Log-ratio (5'/3')", x="TAD data set")
dev.off()

#------------------------------------------------------------------------
stop("Stop execution here!")
#------------------------------------------------------------------------

#=======================================================================
# iterate over different bin numbers and all combination for individual plots and statistics
#=======================================================================

# iterate over bin numbers:
for (nBin in N_BIN_LIST){
    
    # nBin=40
    summaryTab = data.frame()
        
    # Iterate over each set of TADs
    for (TADname in names(allTADs)) {
#~     for (TADname in c("Rao_GM12878")) {
#~     for (TADname in c("Rao_GM12878_nonOverlapping", "Rao_GM12878")) {
        
        #TADname = "Rao_GM12878"
        TAD = allTADs[[TADname]]
        
        # resize TADs by +-50% and divide them into equal sized bins
        TADreg = TAD
        ranges(TADreg) = IRanges(start(TAD) - .5 * width(TAD), end(TAD) + .5 * width(TAD))
        
        # drop TADs that extends out of the chromosome space
        withinChrom = width(TADreg) == width(trim(TADreg))
        TADreg = TADreg[withinChrom]
        
        # make nBin equal sized bins for each TAD
        TADbins = tile(TADreg, n=nBin)
        seqinfo(TADbins) <- seqInfo
        
        # transpose the list to have always the i-th bin together
        TADbinsList = transposeBinList(TADbins, nBin)
        TADbinsSize = width(TADbinsList[[1]])
    
        # get bins arround TAD boundaries
        BoundaryBins = binsAroundTADboundaries(TAD, windowSize=WINDOW_SIZE, nbins=nBin)
        message("INFO: Finished calculation of bins.")
    
        # transform bin list to get each i-th bin together
        boundaryBinList = transposeBinList(BoundaryBins, nBin)
    
        #=======================================================================
        # count regions in Bins of relative size along window around TAD
        #=======================================================================
        
        regInBinSum = rbind()
        regInBinSumPlus = rbind()
        regInBinSumMinus = rbind()

        for (typeName in names(geneTypeTssList)){
            
            regType = geneTypeTssList[[typeName]]
            
            chromsOfInterest <- c("chr4", "chr16", "chr19")
            regionOfInterest <- GRangesList(c( 
                list(regType),
                lapply(chromsOfInterest, 
                    function(chr) geneTypePerChormList[[typeName]][[chr]]
                )
            ))
            names(regionOfInterest) <- c(typeName,  paste0(typeName, "_", chromsOfInterest))
            
            for (regName in names(regionOfInterest)){
                
                reg = regionOfInterest[[regName]]
                
                # count for each bin the number of regions overlapping the bin
                countsInBins = lapply(TADbinsList, countOverlaps, reg)
                countsInBinsPlus = lapply(TADbinsList, countOverlaps, reg[strand(reg) == "+"])
                countsInBinsMinus = lapply(TADbinsList, countOverlaps, reg[strand(reg) == "-"])
                
                names(countsInBins) = paste0("bin_", 1:length(countsInBins))
                names(countsInBinsPlus) = paste0("bin_", 1:length(countsInBinsPlus))
                names(countsInBinsMinus) = paste0("bin_", 1:length(countsInBinsMinus))
                                
                # get the mean/sd count over all i-th bins
                sumCount = apply(as.data.frame(countsInBins), 2, sum)
                sumCountPlus = apply(as.data.frame(countsInBinsPlus), 2, sum)
                sumCountMinus = apply(as.data.frame(countsInBinsMinus), 2, sum)
                
                # test total sum of positve/negative strand counts in first and second half of the TAD
                #For 4 bin case: contTab <- rbind(sumCountPlus[2:3], sumCountMinus[2:3])
                firstHalfBins = (1:nBin)[(nBin/4+1):(nBin/2)]
                secondHalfBins = (1:nBin)[(nBin/2+1):(nBin*3/4)]
                contTab <- matrix(c(
                    sum(sumCountPlus[firstHalfBins]),sum(sumCountPlus[secondHalfBins]),
                    sum(sumCountMinus[firstHalfBins]),sum(sumCountMinus[secondHalfBins])
                    ),2, byrow=TRUE)
                fisherTest <- fisher.test(contTab)
                
                # add values to matrix
                regInBinSum = rbind(regInBinSum, sumCount)
                regInBinSumPlus = rbind(regInBinSumPlus, sumCountPlus)
                regInBinSumMinus = rbind(regInBinSumMinus, sumCountMinus)
                summaryTab = rbind(summaryTab, c(sum(sumCountPlus[firstHalfBins]), sum(sumCountPlus[secondHalfBins]), "+", regName, TADname))
                summaryTab = rbind(summaryTab, c(sum(sumCountMinus[firstHalfBins]), sum(sumCountMinus[secondHalfBins]), "-", regName, TADname))
                    
                colReg = COL_PAIRED_2[which(typeName == names(geneTypeTssList))]        
                colRegPlus = COL_PAIRED_2[which(typeName == names(geneTypeTssList))]        
                colRegMinus = COL_PAIRED_1[which(typeName == names(geneTypeTssList))]        
        
                outFile = paste0(outPrefix, ".nBin_", nBin, ".", TADname, ".", regName, ".counts_along_TADs.pdf")
                plotCountsAroundTADwindow(sumCount, outFile, nbins=nBin, col=colReg, main=regName, ylab="Counts per bin")
        
                outFilePlus = paste0(outPrefix, ".nBin_", nBin, ".", TADname, ".", regName, ".pos_counts_along_TADs.pdf")
                plotCountsAroundTADwindow(sumCountPlus, outFilePlus, nbins=nBin, col=colRegPlus, main=regName, ylab="Counts per bin", type="b", pch=-8853)
        
                outFileMinus = paste0(outPrefix, ".nBin_", nBin, ".", TADname, ".", regName, ".neg_counts_along_TADs.pdf")
                plotCountsAroundTADwindow(sumCountMinus, outFileMinus, nbins=nBin, col=colRegMinus, main=paste(regName, "p =", signif(fisherTest$p.value, 3)), ylab="Counts per bin", type="b", pch=-8854)
                
            }
        }
        
        row.names(regInBinSum) = paste0(rep(names(geneTypeTssList), each=length(names(regionOfInterest))), "_", rep(c("total", chromsOfInterest), length(geneTypeTssList)))
        row.names(regInBinSumPlus) = paste0(rep(names(geneTypeTssList), each=length(names(regionOfInterest))), "_", rep(c("total", chromsOfInterest), length(geneTypeTssList)))
        row.names(regInBinSumMinus) = paste0(rep(names(geneTypeTssList), each=length(names(regionOfInterest))), "_", rep(c("total", chromsOfInterest), length(geneTypeTssList)))
    #~     row.names(regInBinSD) = names(geneTypeTssList)
        
        # wirte values to table output
        write.table(regInBinSum, paste0(outPrefix, ".nBin_", nBin, ".", TADname, ".all.sum_counts_along_TADs.csv"), sep="\t", quote=FALSE, col.names=NA)
        write.table(regInBinSumPlus, paste0(outPrefix, ".nBin_", nBin, ".", TADname, ".all.sum_pos_counts_along_TADs.csv"), sep="\t", quote=FALSE, col.names=NA)
        write.table(regInBinSumMinus, paste0(outPrefix, ".nBin_", nBin, ".", TADname, ".all.sum_neg_counts_along_TADs.csv"), sep="\t", quote=FALSE, col.names=NA)
    

        #=======================================================================
        # count regions in Bins around TAD boundaries
        #=======================================================================
        for (regName in names(geneTypeTssList)){
        
            reg = geneTypeTssList[[regName]]

            # count for each bin the number of regions overlapping the bin
            countsInBins = lapply(boundaryBinList, countOverlaps, reg)
            countsInBinsPlus = lapply(boundaryBinList, countOverlaps, reg[strand(reg) == "+"])
            countsInBinsMinus = lapply(boundaryBinList, countOverlaps, reg[strand(reg) == "-"])

            names(countsInBins) = paste0("bin_", 1:length(countsInBins))
            names(countsInBinsPlus) = paste0("bin_", 1:length(countsInBinsPlus))
            names(countsInBinsMinus) = paste0("bin_", 1:length(countsInBinsMinus))
                
            # get the sum/mean/sd count over all i-th bins
            meanCount = apply(as.data.frame(countsInBins), 2, mean)
            meanCountPlus = apply(as.data.frame(countsInBinsPlus), 2, mean)
            meanCountMinus = apply(as.data.frame(countsInBinsMinus), 2, mean)

                
            colReg = COL_PAIRED_2[which(regName == names(geneTypeTssList))]        
            colRegPlus = COL_PAIRED_2[which(regName == names(geneTypeTssList))]        
            colRegMinus = COL_PAIRED_1[which(regName == names(geneTypeTssList))]        
    
            outFile = paste0(outPrefix, ".nBin_", nBin, ".", TADname, ".", regName, ".counts_arround_boundary.pdf")
            plotCountsAroundBoundaries(meanCount, outFile, windowSize=WINDOW_SIZE, nbins=nBin, col=colReg,
            main=regName)

            outFilePlus = paste0(outPrefix, ".nBin_", nBin, ".", TADname, ".", regName, ".pos_counts_arround_boundary.pdf")
            plotCountsAroundBoundaries(meanCountPlus, outFilePlus, windowSize=WINDOW_SIZE, nbins=nBin, col=colRegPlus,
            main=regName, type="b", pch=-8853)

            outFileMinus = paste0(outPrefix, ".nBin_", nBin, ".", TADname, ".", regName, ".neg_counts_arround_boundary.pdf")
            plotCountsAroundBoundaries(meanCountMinus, outFileMinus, windowSize=WINDOW_SIZE, nbins=nBin, col=colRegMinus,
            main=regName, type="b", pch=-8854)

        }
    
        
        colnames(summaryTab) <- c("first", "second", "strand", "gene_type", "TAD")
        save(summaryTab,paste0(outPrefix, ".", TADname, ".TAD_half.summaryTab.txt"))


    }
    
    
#~     pdf(paste0(outPrefix, ".TAD_half.adjacent_vs_sameTAD.barplot.pdf"), w=14, h=7)
#~         
#~         ggplot(adjPlotDFcout, aes(x=adj, y=freq, fill=inTAD)) + geom_bar(position="dodge",stat="identity") +  
#~         facet_grid(species~tissue) +
#~         theme_bw() + scale_fill_manual(values=COL_TAD) + ylim(0, 1.2*yMax) +
#~         theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
#~         geom_text(aes(label=freq), position=position_dodge(width=1), vjust=-0.25, size=3) + 
#~         geom_text(data=annotDF, aes(x=1.5, y=freq+.15*yMax, label=paste0("OR=", signif(ors, 2))), size=3 ) +
#~         geom_text(data=annotDF, aes(x=1.5, y=freq+.1*yMax, label=paste0("p=", signif(pVals, 2))), size=3) + 
#~         labs(y="Adjacent gene pairs", x="")
#~     dev.off()
    
}

#=======================================================================
# save workspace image
#=======================================================================
save.image(WORKIMAGE_FILE)

