if (!require("pacman")) install.packages("pacman")

pacman::p_load(
  "ggplot2",
  "rjson",
  "logging",
  "plyr",
  "reshape2",
  "stringr",
  "lubridate",
  "proxy",
  "Rmisc",
  "gridExtra",
  "scales",
  "tidyr"
)

basicConfig()

Sys.setlocale("LC_TIME", "C")

BATCH_SIZE <- 10000
BIN_WIDTH <- 4000
BINS <- 10

get_document_length <- function(filepath) {
  res <- data.frame(doc_id=character(0), doc_len=integer(0), par_len=integer(0))
  con = file(filepath, "r")
  count <- 0

  while (TRUE) {
    lines = readLines(con, n = BATCH_SIZE)

    if (length(lines) == 0) {
      break
    }

    doc_lens <- lapply(lines, function(line) {
      json <- fromJSON(line)

      pars <- lapply(json$contents, function(c) {
        if (length(c$subtype) > 0 && c$subtype == 'paragraph') {
          gsub('<.*?>', '', c$content)
        } else {
          NULL
        }
      })

      pars <- pars[!sapply(pars, is.null)]
      
      doc_id = json$id
      doc_len <- nchar(do.call(paste, pars))
      par_len <- nchar(do.call(paste, head(pars, 3)))
      n_words <- sapply(strsplit(do.call(paste, pars), " "), length)
      #n_words <- lengths(gregexpr("[A-z]\\W+", do.call(paste, pars))) + 1L 

      if (length(doc_id) < 1 || length(doc_len) < 1 || length(par_len) < 1) {
        return(data.frame(doc_id=character(0), doc_len=character(0), par_len=character(0)))
      }

      data.frame(doc_id=json$id, doc_len=doc_len, par_len=par_len, n_words=n_words)
    })

    res <- rbind.fill(c(list(res), doc_lens))

    count <- count + length(lines)
    loginfo("%d documents processed", count)
    #break
  }

  close(con)
  res
}
#loginfo("Getting document length and first-three-paragraphs length")
#doc_length <- get_document_length("data/coll-small.jl")

plot_nwords_distribution <- function(filepath) {
  doc_length <- get_document_length(filepath)
  ggplot(doc_length, aes(x=doc_length$n_words)) + geom_histogram(bins=20,boundary=-0.5) + xlab("Words") + ylab("Documents")
}
#plot_nwords_distribution("data/coll-small.jl")

generate_csv <- function(doc_length, doc_length_path) {
  #dir.create("output/", showWarnings = F)
  #doc_length_path <- c("output/", filename)
  write.csv(doc_length, gzfile(doc_length_path), row.names = F)
}
#loginfo("Saving result")
#generate_csv(doc_length = doc_length, doc_length_path = "output/wapo-doc_length-all.csv.gz")

read_csv <- function(doc_length_path) {
  res <- read.csv(file=gzfile(doc_length_path), header=TRUE, sep=",")
  res
}
#loginfo("Getting document length from file")
#doc_length <- read_csv(doc_length_path = "output/wapo-doc_length-all.csv.gz")

plot_data <- function(doc_length) {
  doc_length <- doc_length[order(doc_length$doc_len), ]
  doc_length$n <- 1:nrow(doc_length)
  doc_length <- melt(doc_length, id.vars=c("doc_id", "n"))
  
  ggplot(doc_length, aes(x=n, y=value, color=variable)) +
    geom_smooth() +
    scale_color_discrete("Part", labels=c("Full content", "First three paragraphs")) +
    xlab("Documents") +
    ylab("Length") +
    theme(legend.position="top")
}
#loginfo("Draw graph from data")
#plot_data(doc_length = doc_length)

read_features_file <- function(features_file_path) {
  res <- read.csv(file=gzfile(features_file_path), header=TRUE, sep="\t")
  res
}
#loginfo("Getting features from file")
#features <- read_features_file("data/features-basic6-trec-notext-small.tsv")

plot_sentiment <- function(filefeatures) {
  features <- read_features_file(filefeatures)
  features <- features[!(is.na(features$SentimentAnalysis) | features$SentimentAnalysis=="null"), ]
  ggplot(features, aes(x=features$SentimentAnalysis, fill=features$SentimentAnalysis)) +
    geom_bar() +
    scale_fill_discrete("Sentiment") +
    xlab("Sentiment") +
    ylab("Documents") +
    theme(legend.position="none")
}
#loginfo("Draw graph sentiment")
#plot_sentiment("data/features-basic6-trec-notext-small.tsv")

plot_readability <- function(filefeatures) {
  features <- read_features_file(filefeatures)
  features <- features[!(is.na(features$ReadingComplexity) | features$ReadingComplexity=="null"), ]
  features$ReadingComplexity <- sub("~¨-\\*.*$", "", features$ReadingComplexity)
  positions <- factor(features$ReadingComplexity, levels <- c("5th_grade", "6th_grade", "7th_grade",  "8th_9th_grade", "10th_12th_grade", "College", "College_graduate"))
  ggplot(features, aes(x=positions, fill=positions)) +
    #ggplot(features, aes(x=sub("~¨-\\*.*$", "", features$ReadingComplexity), fill=sub("~¨-\\*.*$", "", features$ReadingComplexity))) +
    geom_bar() +
    scale_fill_brewer("Levels") +
    xlab("Levels") +
    ylab("Documents") +
    theme(legend.position="none",axis.text.x = element_text(angle = 45, hjust = 1))#axis.text=element_text(size=4))
}
#plot_readability("data/features-basic6-trec-notext-small.tsv")

plot_named_entities <- function(filefeatures) {
  features <- read_features_file(filefeatures)
  features <- features[!(is.na(features$NamedEntities) | features$NamedEntities=="null"), ]
  entities <- as.data.frame(table(unlist(str_split(features$NamedEntities, "\\|")), dnn = list("entity")), responseName = "freq")
  entities <- head(entities[order(entities$freq, decreasing = TRUE), ], 20)
  ggplot(entities, aes(x=reorder(entity, freq), y=freq, fill = freq)) + 
  geom_bar(stat="identity") +
  scale_fill_gradient(low = "blue", high = "blue") + 
  xlab("Entities") +
  ylab("Documents") +
  theme(legend.position="none") +
  coord_flip() 
}
#plot_named_entities("data/features-basic6-trec-notext-small.tsv")

plot_emotions_ocurrences <- function(filefeatures) {
  features <- read_features_file(filefeatures)
  features <- features[!(is.na(features$EmotionCategories) | features$EmotionCategories=="null"), ]
  #features$EmotionCategoriesName <- sub("~¨-\\*.*$", "", features$EmotionCategories)
  features$EmotionCategoriesValue <- gsub("\\]", "", gsub("\\[", "", gsub("^.*~¨-\\*", "", features$EmotionCategories)))
  features$EmotionCategoriesList <- gsub(", ", "|", gsub(";[^\\,]*", "", features$EmotionCategoriesValue))
  emotlist <- as.data.frame(table(unlist(str_split(features$EmotionCategoriesList, "\\|")), dnn = list("emot")), responseName = "freq")
  ggplot(emotlist, aes(x=reorder(emot, freq), y=freq, fill = freq)) + 
    geom_bar(stat="identity") +
    scale_fill_gradient(low = "blue", high = "blue") + 
    xlab("Emotions") +
    ylab("Documents") +
    theme(legend.position="none") +
    coord_flip() 
}
#plot_emotions_ocurrences("data/features-basic6-trec-notext-small.tsv")

generate_emotions_weight <- function(filefeatures) {
  features <- read_features_file(filefeatures)
  features <- features[!(is.na(features$EmotionCategories) | features$EmotionCategories=="null"), ]
  #features$EmotionCategoriesName <- sub("~¨-\\*.*$", "", features$EmotionCategories)
  features$EmotionCategoriesValue <- gsub("\\]", "", gsub("\\[", "", gsub("^.*~¨-\\*", "", features$EmotionCategories)))
  features$EmotionCategoriesList <- gsub(", ", "|", features$EmotionCategoriesValue)
  emotlist <- as.data.frame(table(unlist(str_split(features$EmotionCategoriesList, "\\|")), dnn = list("emot")), responseName = "freq")
  emotlist$Label <- gsub(";.*$", "", emotlist$emot)
  emotlist$Weight <- as.numeric(gsub("^.*;", "", emotlist$emot))
  emotlist$emot <- NULL
  emotlist$freq <- NULL
  emotlist
}

generate_emotions_weight_aggr <- function(filefeatures) {
  emotlist <- generate_emotions_weight(filefeatures)
  aggr <- aggregate(emotlist$Weight, by=list(Category=emotlist$Label), FUN=sum)
  colnames(aggr) <- c("Emotions", "Weight")
  aggr <- aggr[order(aggr$Weight, decreasing = TRUE), ]
  listgenerate <- list("emotlist" = emotlist, "aggr" = aggr)
  listgenerate
}
#aggr <- generate_emotions_weight_aggr("data/features-basic6-trec-notext-small.tsv")

plot_emotions_weight <- function(filefeatures) {
  listgenerate <- generate_emotions_weight_aggr(filefeatures)
  aggr <- listgenerate$aggr
  ggplot(aggr, aes(x=reorder(Emotions, Weight), y=Weight, fill = Weight)) + 
    geom_bar(stat="identity") +
    scale_fill_gradient(low = "blue", high = "blue") + 
    xlab("Emotions") +
    ylab("Weight") +
    theme(legend.position="none") +
    coord_flip() 
}
#plot_emotions_weight("data/features-basic6-trec-notext-small.tsv")

plot_emotion_distribution_weight <- function(filefeatures, emot) {
  listgenerate <- generate_emotions_weight(filefeatures)
  emotlist <- listgenerate$emotlist 
  emotlist <- emotlist[emotlist$Label == emot, ]
  ggplot(emotlist, aes(x=emotlist$Weight)) + geom_histogram(bins=5)
}
#plot_emotion_distribution_weight("data/features-basic6-trec-notext-small.tsv", "self-pride")

plot_emotion_distribution_weight_topn <- function(filefeatures, n) {
  listgenerate <- generate_emotions_weight_aggr(filefeatures)
  aggr <- listgenerate$aggr
  aggr <- head(aggr[order(aggr$Weight, decreasing = TRUE), ], n)
  emotlist <- listgenerate$emotlist
  lg <- list()
  for (i in 1:n) 
  local({
    i <- i
    emot <- aggr[i,]$Emotions
    agwe <- emotlist[emotlist$Label == emot,] 
    p1 <- ggplot(data = agwe, aes(x=agwe$Weight)) +
      geom_histogram(bins=5,fill="blue") + 
      ylab("weight") + 
      xlab(emot)
    lg[[i]] <<- p1
  })
  grid.arrange(grobs = lg, ncol = 2)
}
#plot_emotion_distribution_weight_topn("data/features-basic6-trec-notext-small.tsv", 6)

getSeason <- function(DATES) {
  WS <- as.Date("2012-12-15", format = "%Y-%m-%d") # Winter Solstice
  SE <- as.Date("2012-3-15",  format = "%Y-%m-%d") # Spring Equinox
  SS <- as.Date("2012-6-15",  format = "%Y-%m-%d") # Summer Solstice
  FE <- as.Date("2012-9-15",  format = "%Y-%m-%d") # Fall Equinox
  
  # Convert dates from any year to 2012 dates
  d <- as.Date(strftime(DATES, format="2012-%m-%d"))
  
  ifelse (d >= WS | d < SE, "Winter",
          ifelse (d >= SE & d < SS, "Spring",
                  ifelse (d >= SS & d < FE, "Summer", "Fall")))
}

time_published_histogram <- function(filetrecextra) {
  extra <- read.csv(file=filetrecextra, header=TRUE, sep="\t")
  extra$published_date_real <- as.Date(as.POSIXct(extra$published_date/1000, origin="1969-12-31"))
  ggplot(extra, aes(x=published_date_real)) + geom_histogram(binwidth=30, colour="white") +
    scale_x_date(labels = date_format("%Y-%b"),
                 #breaks = seq(as.Date("2011-10-01")-5, as.Date("2015-04-01")+5, 30),
                 limits = c(as.Date("2011-12-01"), as.Date("2015-04-01"))) +
    ylab("Frequency") + xlab("Year and Month") +
    theme(legend.position="none")
    #theme(legend.position="none",axis.text.x = element_text(angle = 0, hjust = 1))
}
#time_published_histogram("data/trec-extra.tsv")

# ========== Rerank methods ==========
#LAMBDA <- 0.5
LAMBDA <- 0.85

# Show concrete columns (by name) of dataframe
#features_df[, c("id","SentimentAnalysis")] 

# Delete column of dataframe
#r1[, -1]

# Vector similarity
#simil(matrix(c(1,2,3,  1,2,3), nrow=2, byrow=T), method="cosine")

maxS <- function(di, dJ, features_df) {
  df <- data.frame(matrix(ncol = 2, nrow = 0))
  colnames(df) <- c("id", "sim")
  for (dj in dJ) {
    sim <- simil(matrix(c(features_df[which(features_df$id == di), -1],  features_df[which(features_df$id == dj), -1]), nrow=2, byrow=T), method="cosine")
    df[nrow(df)+1,] <- c(dj, sim)
  }
  as.numeric(max(df$sim))
}
rerank <- function(features_df, r1) {
  r1$norm_score <- r1$V5/max(r1$V5)
  r1split <- split(r1, r1$V1)
  
  s_rerank <- NULL
  for (topic in as.character(unique(r1$V1))) {
    s <- NULL
    rs <- r1split[[topic]]
    rs <- cbind(mmr = 1.0, rs)
  
    s <- rbind(s, head(rs,1))
    rs <- rs[-1,]
  
    while(nrow(rs) > 0) {
      print(topic)
      print(nrow(rs))
      #df <- data.frame(matrix(ncol = 2, nrow = 0))
      #colnames(df) <- c("id", "mmr")
      for(i in 1:nrow(rs)){
        mmr <- LAMBDA * (rs[i,]$norm_score - (1-LAMBDA)*maxS(rs[i,]$V3, s$V3, features_df))
        #df[nrow(df)+1,] <- c(rs_doc, mmr)
        rs[i,]$mmr <- mmr
      }
      #df[which.max(df$mmr),]$id
      s <- rbind(s, rs[which.max(rs$mmr),])
      rs <- rs[-which.max(rs$mmr),]
    }
    s$rank <- seq.int(nrow(s))
    s$score <- seq(1,0,length.out=nrow(s))
    
    s_rerank <- rbind(s_rerank, s)
  }
  s_rerank$V6 <- "feup-run321"
  s_rerank <- s_rerank[, c("V1", "V2", "V3", "V4", "V5", "rank", "score", "mmr", "V6", "norm_score")]
  s_rerank
}
reduce_rank_file <- function(input_rank_file, output_rank_file, entries_per_topic) {
  r1 <- read.csv(file=input_rank_file, header=FALSE, sep=" ")
  r1split <- split(r1, r1$V1)
  
  s_rerank <- NULL
  for (topic in as.character(unique(r1$V1))) {
    s <- NULL
    s <- r1split[[topic]]
    s <- head(s, entries_per_topic)

    s_rerank <- rbind(s_rerank, s)
  }
  write.table(s_rerank,file=output_rank_file,sep=" ",quote = F,col.names = F, row.names = F)
}
#reduce_rank_file("data/feup-run2.res", "output/reduced.res", 100)

# Rerank process
rerank_process <- function(filerun, filematrix, fileout) {
  r1 <- read.csv(file=filerun, header=FALSE, sep=" ")
  features_df <- read.csv(file=filematrix, header=TRUE, sep="\t")
  #+temp try less features
  #features_df <- features_df[, c("id", "SentimentAnalysis", "ReadingComplexity")]
  features_df <- features_df[, grep("^id$|^SentimentAnalysis|^ReadingComplexity|^EmotionCategories", colnames(features_df), value=T)] #^Keywords|^NamedEntities|
  s_rerank <- rerank(features_df, r1)
  #-temp Only run cols
  #s_rerank <- s_rerank[, c("V1", "V2", "V3", "rank", "score", "V6")]
  write.table(s_rerank,file=fileout,sep=" ",quote = F, col.names = F, row.names = F)
}
#rerank_process("data/feup-run1.res", "data/run1-matrix-bin-discret.tsv", "output/out.res")

# ========== Rerank methods ==========

get_ids_topn_authors <- function(filefeaturesextra, n) {
  featuresextra <- read_features_file(filefeaturesextra)
  featuresextra <- featuresextra[!(is.na(featuresextra$author) | featuresextra$author=="null" | featuresextra$author==""), ]
  featuresextra$author <- gsub( ", ", "|", as.character(featuresextra$author) )
  featuresextra$author <- gsub( " and ", "|", as.character(featuresextra$author) )
  featuresextra$author <- gsub( "; ", "|", as.character(featuresextra$author) )
  featuresextra$author <- gsub( "— ", "", as.character(featuresextra$author) )
  authors <- head(authors[order(authors$freq, decreasing = TRUE), ], n)
}

get_authors_extra_features <- function(filefeaturesextra) {
  featuresextra <- read_features_file(filefeaturesextra)
  featuresextra <- featuresextra[!(is.na(featuresextra$author) | featuresextra$author=="null" | featuresextra$author==""), ]
  featuresextra$author <- gsub( ", ", "|", as.character(featuresextra$author) )
  featuresextra$author <- gsub( " and ", "|", as.character(featuresextra$author) )
  featuresextra$author <- gsub( "; ", "|", as.character(featuresextra$author) )
  featuresextra$author <- gsub( "— ", "", as.character(featuresextra$author) )
  featuresextra$author <- gsub( "’", "'", as.character(featuresextra$author) )
  authors <- as.data.frame(table(unlist(str_split(featuresextra$author, "\\|")), dnn = list("author")), responseName = "freq")
  df_separate <- featuresextra[, c("author", "type")]
  #separate_rows don't works, alternative:
    s <- strsplit(df_separate$author, split = "\\|")
    df_separate <- data.frame(type = rep(df_separate$type, sapply(s, length)), author = unlist(s))
  #df_separate %>% separate_rows(author, sep=",")
  freq_author <- factor(df_separate$type)
  listgenerate <- list("authors" = authors, 
                       "freq_author" = freq_author, 
                       "df_separate" = df_separate, 
                       "featuresextra" = featuresextra)
  listgenerate
}
#listgenerate <- get_authors_extra_features('data/trec-extra-small.tsv')

plot_authors_distrib <- function(filefeaturesextra) {
  authors <- get_authors_extra_features(filefeaturesextra)
  authors <- listgenerate$authors
  authors <- head(authors[order(authors$freq, decreasing = TRUE), ], 10)
  ggplot(authors, aes(x=reorder(author, freq), y=freq, fill = freq)) + 
    geom_bar(stat="identity") + 
    scale_fill_gradient(low = "blue", high = "blue") + 
    xlab("Authors") +
    ylab("Documents") +
    theme(legend.position="none") +
    coord_flip() 
}
#plot_authors_distrib('data/trec-extra.tsv')

plot_authors_distrib <- function(filefeaturesextra) {
  authors <- get_authors_extra_features(filefeaturesextra)
  authors <- head(authors[order(authors$freq, decreasing = TRUE), ], 10)
  ggplot(authors, aes(x=reorder(author, freq), y=freq, fill = freq)) + 
    geom_bar(stat="identity") + 
    scale_fill_gradient(low = "blue", high = "blue") + 
    xlab("Authors") +
    ylab("Documents") +
    theme(legend.position="none") +
    coord_flip() 
}
#plot_authors_distrib('data/trec-extra.tsv')

get_topics_extra_features <- function(filefeaturesextra) {
  featuresextra <- read.csv(file=filefeaturesextra, header=TRUE, sep="\t")
  featuresextra <- featuresextra[!(is.na(featuresextra$article_url) | featuresextra$article_url=="null" | featuresextra$article_url==""), ]
  topics <- as.data.frame(table(unlist(str_split(featuresextra$article_url, "\\|")), dnn = list("topic")), responseName = "freq")
  topics
}  
plot_topics_distrib <- function(filefeaturesextra) {
  topics <- get_topics_extra_features(filefeaturesextra)
  topics <- head(topics[order(topics$freq, decreasing = TRUE), ], 20)
  ggplot(topics, aes(x=reorder(topic, freq), y=freq, fill = freq)) + 
    geom_bar(stat="identity") + 
    scale_fill_gradient(low = "blue", high = "blue") + 
    xlab("Topics") +
    ylab("Documents") +
    theme(legend.position="none") +
    coord_flip() 
}
#plot_topics_distrib('data/trec-extra.tsv')
