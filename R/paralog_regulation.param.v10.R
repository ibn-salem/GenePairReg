########################################################################
#
# This script contains parameters for the paralog_regulation.R analysis.
#
########################################################################

#-----------------------------------------------------------------------
# External data file paths
#-----------------------------------------------------------------------
REGMAP_FILE_FANTOM5 = "data/Andersson2014/enhancer_tss_associations.bed"
EH_FILE_FANTOM5 = "data/Andersson2014/permissive_enhancers.bed"


RaoDomainFiles = c(
    Rao_HeLa="data/Rao2014/GSE63525_HeLa_Arrowhead_domainlist.txt",
    Rao_HUVEC="data/Rao2014/GSE63525_HUVEC_Arrowhead_domainlist.txt",
    Rao_K562="data/Rao2014/GSE63525_K562_Arrowhead_domainlist.txt",
    Rao_KBM7="data/Rao2014/GSE63525_KBM7_Arrowhead_domainlist.txt",
    Rao_NHEK="data/Rao2014/GSE63525_NHEK_Arrowhead_domainlist.txt",
    Rao_IMR90="data/Rao2014/GSE63525_IMR90_Arrowhead_domainlist.txt",
    Rao_GM12878="data/Rao2014/GSE63525_GM12878_primary+replicate_Arrowhead_domainlist.txt"
)

DixonDomainFiles = c(
    Dixon_hESC="data/Dixon2012/hESC.hg18.bed.hg19.bed",
    Dixon_IMR90="data/Dixon2012/IMR90.hg18.bed.hg19.bed"
)

# Mouse and dog TADs from Rudan et al. 2015
RudanFile = "data/Rudan2015/mmc2.xlsx"

#-----------------------------------------------------------------------
# Rao et al. 2014 Hi-C sample
#-----------------------------------------------------------------------
CELL="IMR90"
HIC_RESOLUTION=50*10^3 # 50kb
HIC_DATA_DIR="data/Rao2014"

#-----------------------------------------------------------------------
# Colors used for plotting
#-----------------------------------------------------------------------
# two colors for paralog and non-paralog genes
COL=brewer.pal(9, "Set1")[c(1,9)]   # for paralog vs. sampled genes
COL_RAND=c(COL[1], brewer.pal(8, "Dark2")[8])   # random genes
COL2=brewer.pal(9, "Set1")[c(1,2)]  # for paralog vs. non-paralog
COL_DOMAIN=brewer.pal(9, "Set3")
COL_FAMILY=brewer.pal(8, "Dark2")
COL_EH = brewer.pal(9, "Set1")[5]
COL_TAD = brewer.pal(8, "Set1")[c(3,5)]
COL_ORTHO = c(brewer.pal(12, "Paired")[5], brewer.pal(8, "Pastel2")[8])
COL_SPECIES = brewer.pal(8, "Accent")[1:2]

#-----------------------------------------------------------------------
# Parameters for data loading
#-----------------------------------------------------------------------

# use local data or downlaod data from ensemble
USE_LOCAL = TRUE
USE_LOCAL_HIC_CONTACTS = FALSE
#~ N_CPUS=20

#-----------------------------------------------------------------------
# Parameters critical to the analysis
#-----------------------------------------------------------------------

# number of random permutations of whole data sets
N_RAND=10               

# parameter to adjust bandwidth in density estimation for sampling
DENSITY_BW_ADJUST=0.1   

RANDOM_SEED=13521

MAX_DIST=10^6
DISTAL_MAX_DIST=10^9
DISTAL_MIN_DIST=10^6

DIST_TH=c(10^6, 10^5)

#-----------------------------------------------------------------------
# Version of the analysis and output file paths
#-----------------------------------------------------------------------

VERSION="v10"

outDataPrefix = "results/paralog_regulation/EnsemblGRCh37_paralog_genes"
outPrefix = paste0("results/paralog_regulation/", VERSION, "_maxDist_", MAX_DIST, "_nrand_", N_RAND, "/EnsemblGRCh37_paralog_genes")

# create directory, if not exist
dir.create(dirname(outPrefix), recursive=TRUE, showWarnings = FALSE)

# image file to save temporary and final R session with all data
WORKIMAGE_FILE = paste0(outPrefix, "workspace.Rdata")

