########################################################################
#
# A script provides functionality to sample random gene pairs by 
# maintaining some properties, such as linear distance and shared enhancer. 
#
# It was initially written as for the paralog_regulation.R analysis.
#
########################################################################

require(stringr)        # for some string such as paste0()
require(GenomicRanges)
require(plyr)           # four count() function

# New and faster approach
# 1.) precompute all possible gene pairs within a distance of XMb
#   ID_g1   ID_g2   dist    eh1     eh2
#   3       5       -2341   2       1
#   3       1       3234    2       3
#   ...
# Do this by extending each TSS by +-X/2 Mb and get overlapping TSS

# 2.) Sample according to distance distribution and number of enhancers in source genes
# Precalculate the density d_eh(g) for all number of linked enhancers eh(g) in the 
# set of source genes.
# For each source pair take d_eh(g1,g2) = [d(eh(g1)) * d(eh(g2))] as density.
# Analogusly get the distance distribution density d_dist(pairs) from source pairs.
# Now, from all possible gene pairs sample according to combined weight
# w_p = d_eh(pair) * d_dist(pair)
# 

#-----------------------------------------------------------------------
# get all possible gene pairs within a given maximal distance as data frame
# with annotations like distance and linked enhancers
#-----------------------------------------------------------------------
getAllGenePairs <- function(tssGR, maxDist, minDist=0){

    # calculate overlap all possible gene pairs within maxDist bp
    hits = findOverlaps(tssGR, resize(tssGR, 2*maxDist+1, fix="center", ignore.strand=TRUE), ignore.strand=TRUE)
    
    # convert hits objec to data.frame
    hitDF = as.data.frame(hits)
    names(hitDF) <- c("IDg1", "IDg2")

    # remove pairs with same gene 
    hitDF = hitDF[hitDF$IDg1 != hitDF$IDg2, ]
    
    # add distance
    hitDF$dist = start(tssGR[hitDF$IDg2]) - start(tssGR[hitDF$IDg1])

    # remove pars with distance smaller than minDist
    hitDF = hitDF[abs(hitDF$dist) >= minDist,]
    
    # annotate the gene pairs with number of enhancers
    hitDF$EHg1 = tssGR[hitDF$IDg1]$linked_enhancer
    hitDF$EHg2 = tssGR[hitDF$IDg2]$linked_enhancer
    
    return(hitDF)

}

#-----------------------------------------------------------------------
# To sample random gene pairs get probability weights of all pairs 
# according to the distribution of distances and linked enhancer in input
# gene pair set
#-----------------------------------------------------------------------
getSampleWeightsByDistAndEnhancers <- function(hitDF, tssGR, sourcePairs, ...){
    
    # get probability density for the number of linked enhancers
    weightEH = weightByEnhancers(tssGR, c(sourcePairs[,1], sourcePairs[,2]))
    
    # combine the probabilites from both gene pair partners by assuming independence
    pairWeightEH = ( weightEH[hitDF[,1]] * weightEH[hitDF[,2]] )
    pairWeightEH = pairWeightEH / sum(pairWeightEH)
    
    # get observed probabilty density of distances in source pairs
    distDens = approxfun(density(abs(sourcePairs$dist), ...))
    pairWeightDist = distDens(abs(hitDF$dist))

    # if probability is NA set it to 0
    pairWeightDist[is.na(pairWeightDist)] = 0
    pairWeightDist = pairWeightDist / sum(pairWeightDist)
    
    # combine the probabilities for linked enhancer and linear distance by multiplication by assuming independence
    pairWeight = ( pairWeightEH * pairWeightDist ) 
    pairWeight  = pairWeight / sum(pairWeight)
    
    return(pairWeight)
}


#-----------------------------------------------------------------------
# returns sampling weights to sample from samp with probabilities observed in obs
#
#  obs  := vector of observed values according to which the sampling should be done (e.g distances observed for paralog gene pairs).
#  population := vector of all values in the total population from which one wants to sample (e.g distances of all gene pairs) 
#  breaks := breaks used for sampling resolution (see breaks argument in hist() function).
#
#-----------------------------------------------------------------------
weightsByBin <- function(obs, population, breaks=50){

    breaksAll <- hist(c(obs, population), breaks=breaks, plot=FALSE)$breaks
        
    # calculate the number of observation for nBin equal sized bins
    hObs <- hist(obs, breaks=breaksAll, plot=FALSE)
    
    # get for each individual in the population the bin index
    binPop <- .bincode(population, breaksAll, include.lowest=TRUE)
    
    # get counts per bin in the population
    hPop <- hist(population, breaks=breaksAll, plot=FALSE)    

    # define the relative counts per bin in the observed data set and the relative counts per bin in the population as bias in the population
#~     obsFreq <- hObs$counts / length(obs)
#~     populationBias <- hPop$counts / length(population)
    
    
    # get the number of observed counts normalized to one as weight
    # normalize the number of observed counts by the bias observed in the population 
    weight <- hObs$counts[binPop] / hPop$counts[binPop] 
#~     weight <- obsFreq[binPop] / populationBias[binPop] 

    # remove NA's, e,g, bis not observed in obs but in population. Set their probability to zero 
    weight[is.na(weight)] = 0
        
    # normalize the weights to sum up to 1
    weightNormed <- weight / sum(weight)
    
    return(weightNormed)
}

#-----------------------------------------------------------------------
# To sample random gene pairs get probability weights of all pairs 
# according to the distribution of distances and linked enhancer in input
# gene pair set
#-----------------------------------------------------------------------
weightsByBinDistAndEnhancers <- function(distWeight, sourcePairs, hitDF, tssGR){
    
    # get probability density for the number of linked enhancers
    weightEH <- weightByEnhancers(tssGR, c(sourcePairs[,1], sourcePairs[,2]))
    
    # combine the probabilites from both gene pair partners by assuming independence
    pairWeightEH <- ( weightEH[hitDF[,1]] * weightEH[hitDF[,2]] )
    pairWeightEH <- pairWeightEH / sum(pairWeightEH)
    
    # combine the probabilities for linked enhancer and linear distance by multiplication by assuming independence
    pairWeight <- ( pairWeightEH * distWeight ) 
    pairWeight  <- pairWeight / sum(pairWeight)
    
    return(pairWeight)
}

#-----------------------------------------------------------------------
# Returns probabilites for sampling from a population according to the 
# the frequencies of a variable (factor) observed in an observed set.
# obs           := vector of variable (factor) of observed set
# population    := vector of variable (factor) in the population
#-----------------------------------------------------------------------
weightsByFactorFreq <- function(obs, population){

    # annotate all pairs with sameStrand information
#~     freqTabObs <- table(obs) / length(obs)
#~     freqTabPop <- table(population) / length(population)
    freqObsDF <- count(as.vector(obs))
    freqPopDF <- count(as.vector(population))

    # convert the factor to character
#~     factStrPop = as.character(population)
    
    # take ratio of frequencies in opserved set and weight for randomly sampling from population set
#~     weight = freqTabObs[factStrPop] / freqTabPop[factStrPop]
    weight = freqObsDF[match(as.vector(population), freqObsDF$x), "freq"] / freqPopDF[match(as.vector(population), freqPopDF$x), "freq"]
    
    # remove NA's, e,g, number of enhancers not observed in paralogs but in set of all genes. Set their probability to zero 
    weight[is.na(weight)] = 0
    
    # normalize weights to 1
    propability = weight / sum(weight)
    
    return(propability)
}

#-----------------------------------------------------------------------
# Get sampling weight only based on distance (or other column by "colName")
#-----------------------------------------------------------------------
getSampleWeightsByDist <- function(hitDF, sourcePairs, colName="dist", ...){

    # get observed probabilty density of distances in real source pairs
    distDens = approxfun(density(abs(sourcePairs[,colName]), ...))
    pairWeightDist = distDens(abs(hitDF[,colName]))

    # set prob of NAs to zero
    pairWeightDist[is.na(pairWeightDist)] = 0
    return(pairWeightDist / sum(pairWeightDist, na.rm=TRUE))
}

#-----------------------------------------------------------------------
# Get sampling weight in log space
#-----------------------------------------------------------------------
getSampleWeightsByDistLog <- function(hitDF, sourcePairs, colName="dist", ...){

    # get observed probabilty density of distances in real source pairs
    distDens = approxfun(density(log10(abs(sourcePairs[,colName])), ...))
    pairWeightDist = distDens(log10(abs(hitDF[,colName])))

    # set prob of NAs to zero ( so they will not be sampled)
    pairWeightDist[is.na(pairWeightDist)] = 0
    return(pairWeightDist / sum(pairWeightDist, na.rm=TRUE))
}

#-----------------------------------------------------------------------
# sample pairs from the input gene pair set according to given sampling weights
#-----------------------------------------------------------------------
sampleFromAllPairsByWeight <- function(n, hitDF, tssGR, weight){
        
    # sample random pairs from input pairs according to weights
    pairIDX <- sample.int(nrow(hitDF), n, prob=weight, replace=TRUE)
    
    # construct gene pair DF from sampled pairs
    rP <- data.frame(
        g1=as.character(names(tssGR)[hitDF[pairIDX,1]]),
        g2=as.character(names(tssGR)[hitDF[pairIDX,2]]),
        dist=hitDF[pairIDX, "dist"],
    stringsAsFactors=FALSE)
    
    return(rP)
    
}
# rP = sampleFromAllPairs( n=100, hitDF=allGenePairs,tssGR, sourcePairs=cisPairs[abs(cisPairs$dist) <= MAX_DIST, ], sourceGenes=paralogs[,1])
         

#-----------------------------------------------------------------------
# sample randomly from vector, even from size one vector with integer elements
#-----------------------------------------------------------------------
sample.vec <- function(x, ...) x[sample(length(x), ...)]

#-----------------------------------------------------------------------
# get weights for sampling gene pairs from popPairIDs according to the number 
# of linked enhancers to each gene in obsPairs
#-----------------------------------------------------------------------
weightPairsByEnhancers <- function(tssGR, obsPairs, popPairIDs){
    
    # combine enhancer number of both gene in pair by taking the sum
    obs <- tssGR[c(obsPairs[,1], obsPairs[,2])]$linked_enhancer 
    pop <- tssGR$linked_enhancer[c(popPairIDs[,1], popPairIDs[,2])]
    
    # get distribution function of linked enhancer elements in the paralog genes
    obsEhFreqDF <- count(obs)

    # non-adjusted frequencies of enhancers in all genes:
    popEhFreqDF <- count(pop)

    # get the counts in population separately for each gene in the pair
    ehCounts1 = tssGR$linked_enhancer[popPairIDs[,1]]
    ehCounts2 = tssGR$linked_enhancer[popPairIDs[,2]]
    
    # take ratio of enhancers in paralogs and enhancers in all genes as weight for randomly sampling from all genes
    weight1 = obsEhFreqDF[match(ehCounts1, obsEhFreqDF$x), "freq"] / popEhFreqDF[match(ehCounts1, popEhFreqDF$x), "freq"]
    weight2 = obsEhFreqDF[match(ehCounts2, obsEhFreqDF$x), "freq"] / popEhFreqDF[match(ehCounts2, popEhFreqDF$x), "freq"]
    
    # remove NA's, e,g, number of enhancers not observed in paralogs but in set of all genes. Set their probability to zero 
    weight1[is.na(weight1)] = 0
    weight2[is.na(weight2)] = 0
    
    # normalize weights to 1
    weight1 = weight1 / sum(weight1)
    weight2 = weight2 / sum(weight2)

    weightPair <- weight1 * weight2
    propPair <- weightPair / sum(weightPair)
    return(propPair)
}

#-----------------------------------------------------------------------
# get weights for all genes for sampeling according to the distribution 
# of linked enhancers in the set of sourceGenes (paralog genes)
#-----------------------------------------------------------------------
weightByEnhancers <- function(tssGR, sourceNames){

    # non-adjusted frequencies of enhancers in all genes:
    allGenesEnhancerFreqTable = table(mcols(tssGR)[, "linked_enhancer"])
    
    # get distribution function of linked enhancer elements in the paralog genes
    paralogsEnhancerFreqTable = table(mcols(tssGR[sourceNames])[,"linked_enhancer"])
    
    # convert the numbers to character
    ehCounts = as.character(mcols(tssGR)[, "linked_enhancer"])
    
    # take ratio of enhancers in paralogs and enhancers in all genes as weight for randomly sampling from all genes
    weight = paralogsEnhancerFreqTable[ehCounts] / allGenesEnhancerFreqTable[ehCounts]
    
    # remove NA's, e,g, number of enhancers not observed in paralogs but in set of all genes. Set their probability to zero 
    weight[is.na(weight)] = 0
    
    # normalize weights to 1
    weight = weight / sum(weight)
    
    return(weight)
}
# weight = weightByEnhancers(tssGR, paralogs[,1])
# randGenes = sample(genes[,1], nrow(genes), prob=weight, replace=TRUE)

#-----------------------------------------------------------------------
# sample randomly pairs from the entire gene set with equal probabilities
#-----------------------------------------------------------------------
getRandomPairs <- function(n, geneIDs){
    randomPairs = data.frame(
        t(replicate(n, sample(geneIDs, size=2, replace=FALSE))), 
        stringsAsFactors=FALSE)
    names(randomPairs) = c("g1", "g2")
    return(randomPairs)
}
