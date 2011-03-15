# Vocabulink site

SUBDIRS := cgi articles css js
date := $(shell date +%Y-%m-%d)
sync_options := -avz --exclude 'cgi/dist' --exclude 'upload/img/*' --exclude 'upload/audio/pronunciation/*' --exclude '*.muse' --exclude '*.sass' --exclude 'articles/Makefile' --exclude '*.el' --exclude 'css/Makefile' --exclude 'js/Makefile' --exclude 'cgi/*.pdf' --exclude 'cgi/TAGS' --exclude '*.aux' --exclude '*.tex' --exclude '*.ptb' --exclude '*.log' --exclude '*.out' --exclude '._*' --exclude '.DS_Store' --exclude '.sass-cache' --delete articles css etc img js s scripts upload vocabulink.cgi linode:vocabulink/

.PHONY : $(SUBDIRS) all

all : $(SUBDIRS)
	@echo built

backup : backup-database

backup-database :
	pg_dump --host localhost --username vocabulink --create vocabulink | gzip > vocabulink--$(date).sql.gz

sync :
	rsync $(sync_options)

sync-test :
	rsync --dry-run $(sync_options)

$(SUBDIRS) :
	@-$(MAKE) -C $@
