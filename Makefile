S3_BUCKET   = moz-devservices-bmocartons
S3_BUCKET_URI = https://$(S3_BUCKET).s3.amazonaws.com
AWS_PROFILE = bmocartons

DOCKER    = $(SUDO) docker 
BASE_DIR := $(shell pwd)
PERL5LIB := $(BASE_DIR)/lib
VERSION  := $(shell git show --oneline | awk '$$1 {print $$1}')

IMAGE_TAG  = build-$*
SCRIPTS   := $(wildcard scripts/*)

DIRS    ?= bmo/ bmo24/ mozreview/ amazon/ bmo_centos7/
BUNDLES  = $(addsuffix vendor.tar.gz,$(DIRS))

export PERL5LIB DOCKER SUDO S3_BUCKET_URI

list:
	@for dir in $(DIRS); do \
		echo $$(basename $$dir); \
	done

-include depends.mk

bundles: $(BUNDLES)
build: $(patsubst %/,build-%,$(DIRS))
clean: $(patsubst %/,clean-%,$(DIRS))
upload: $(patsubst %/,upload-%,$(DIRS))
snapshots: $(BUNDLES)
	for bundle in $(BUNDLES); do \
		file="$$(dirname $$bundle)/cpanfile.snapshot"; \
		tar -zxf $$bundle $$file; \
		git add $$file; \
	done

s3_uris:
	@for b in $(BUNDLES); do \
		echo $(S3_BUCKET_URI)/$$b; \
	done

s3_buckets:
	@for b in $(BUNDLES); do \
		echo $(S3_BUCKET)/$$b; \
	done


depends.mk: scan-deps $(git ls-files $(DIRS))
	./scan-deps $(DIRS) > $@


ifdef UPDATE_MODULES
%/vendor.tar.gz: build-%
	@echo UPDATE $@
	@./run-and-copy \
		--image "$(IMAGE_TAG)" \
		--cmd update-modules \
		$(patsubst %,-a %,$(UPDATE_MODULES)) \
		/vendor.tar.gz $@
else
%/vendor.tar.gz: build-%
	@echo TAR $@
	@./run-and-copy --image "$(IMAGE_TAG)" --cmd build-bundle /vendor.tar.gz $@

endif

upload-%: %/vendor.tar.gz
	@echo UPLOAD $<
	@aws --profile $(AWS_PROFILE) s3 cp $< s3://$(S3_BUCKET)/$<
	touch $@


build-%: %/Dockerfile %/.dockerignore $(SCRIPTS) 
	@echo BUILD $*
	@cd $* && $(DOCKER) build -m 2G -t $(IMAGE_TAG) .
	@$(DOCKER) images -q $@ > $@

clean-%:
	@echo CLEAN $*
	@rm -vf $*/Dockerfile $*/vendor.tar.gz $*/*.log
	@rm -vfr $*/copy

%/Dockerfile: %/Dockerfile.PL lib/Dockerfile.pm $(SCRIPTS)
	perl $< > $@

.DELETE_ON_ERROR: %/Dockerfile %/vendor.tar.gz

%/.dockerignore: .dockerignore
	cp $< $@

.PHONY: bundles clean-% build clean list upload snapshots
