#
# Build a debian and armbian based initramfs system
#

# TODO:
# - Convert the minimalisation step into an excludes file generator
#   and use that file in the cpio step
# - Add config file list / save to sdcard / load from sdcard package

# Default to just looking in the local directory for config files
CONFIGDIRS ?= .

CONFIG_DISTRO = buster
CONFIG_DEBIAN_ARCH ?= armhf

CONFIG_ROOT_PASS = root

# Directories
BUILD = build
TAG = $(BUILD)/tags
DEBOOT = $(BUILD)/debian.$(CONFIG_DISTRO).$(CONFIG_DEBIAN_ARCH)

BUILD_DEPENDS = \
    multistrap \
    binfmt-support \
    qemu-user-static \
    qemu-system-x86 \
    expect \
    shellcheck \
    python3-jinja2 \
    python3-libarchive-c \
    flake8

# A default target to tell you what other targets might work
all:
	$(info Build a platform neutral debian install)
	$(info Try:)
	$(info - setting CONFIG_DEBIAN_ARCH - eg to armhf)
	$(info - $(MAKE) cpio)
	$(info this will output a cpio file in the build dir)
	$(info (or other variations for i386))
	$(info (possibly setting CONFIG_DISTRO for some special cases))

.PHONY: cpio
cpio:
	$(MAKE) build/debian.$(CONFIG_DISTRO).$(CONFIG_DEBIAN_ARCH).cpio

# Build and boot a test environment
.PHONY: test_run
test_run:
	$(MAKE) -C test

# Run a test script against the booted test environment
.PHONY: test
test: shellcheck flake8
	$(MAKE) -C test prepare
	./scripts/test_harness "make test_run" config_pass=$(CONFIG_ROOT_PASS) tests/*.expect

# A list of all the shell scripts that need linting

# the scripts we run during the build
SHELLSCRIPTS := scripts/packages.addextra scripts/packages.runscripts
SHELLSCRIPTS += scripts/configdir_deps
SHELLSCRIPTS += scripts/authorized_keys_local scripts/authorized_keys_path
# then the scripts that are copied into the build
SHELLSCRIPTS += multistrap.configscript policy-rc.d
# Add the custom phase scripts
SHELLSCRIPTS += packages.d/*.minimise packages.d/*.fixup #packages.d/*.customise

# Add the pre-systemd init system (runs inside the image)
SHELLSCRIPTS += packages.d/_ALWAYS.fixup.add/init \
    packages.d/_ALWAYS.fixup.add/init.d/*

# Add scripts that run inside the image
SHELLSCRIPTS += packages.d/_ALWAYS.fixup.add/usr/local/sbin/config_save \
    packages.d/hostapd.customise.add/usr/local/sbin/hostapd.template \
    packages.d/systemd.customise.add/usr/local/sbin/mesh.setup \
    packages.d/systemd.customise.add/usr/local/sbin/udc.setup

# Run a shell script linter
shellcheck:
	shellcheck $(SHELLSCRIPTS)

# A list of python scripts that need linting
PYTHONSCRIPTS := scripts/cpio-ls
PYTHONSCRIPTS += scripts/multistrapconf-create

# Run a python linter
flake8:
	flake8 $(PYTHONSCRIPTS)

# install any packages needed for this builder
build-depends: $(TAG)/build-depends
$(TAG)/build-depends: Makefile
	sudo apt-get -qq install $(BUILD_DEPENDS)
	$(call tag,build-depends)

# some of the debian packages need a urandom to install properly
$(DEBOOT)/dev/urandom:
	mkdir -p $(DEBOOT)/dev
	sudo mknod $(DEBOOT)/dev/urandom c 1 9

$(TAG)/policy-rc.d.add: policy-rc.d
	sudo mkdir -p $(DEBOOT)/usr/sbin
	sudo cp $< $(DEBOOT)/usr/sbin/policy-rc.d
	$(call tag,policy-rc.d.add)

# a list of files, which contain additional packages to install
packages_lists := $(wildcard $(addsuffix /packages.txt,$(CONFIGDIRS)))

multistrap_jinja := debian.multistrap.jinja
multistrap_jinja_src := $(lastword $(wildcard $(addsuffix /$(multistrap_jinja),$(CONFIGDIRS))))
multistrap_apt_source := $(lastword $(wildcard $(addsuffix /apt.sources/$(CONFIG_DISTRO).list,$(CONFIGDIRS))))

MULTISTRAP_CONF=$(BUILD)/debian.$(CONFIG_DISTRO).multistrap

$(MULTISTRAP_CONF): scripts/multistrapconf-create
$(MULTISTRAP_CONF): $(multistrap_jinja_src) $(packages_lists)
	scripts/multistrapconf-create \
	    --source $(multistrap_apt_source) \
	    --template $(multistrap_jinja_src) \
	    $(addprefix --packagefile=, $(packages_lists)) \
	    --output $@

.PHONY: builddir
builddir:
	mkdir -p $(BUILD)

# multistrap-pre runs the basic multistrap program, installing the packages
# until they need to run native code
$(TAG)/multistrap-pre.$(CONFIG_DEBIAN_ARCH): builddir
$(TAG)/multistrap-pre.$(CONFIG_DEBIAN_ARCH): $(TAG)/policy-rc.d.add
$(TAG)/multistrap-pre.$(CONFIG_DEBIAN_ARCH): $(MULTISTRAP_CONF)
$(TAG)/multistrap-pre.$(CONFIG_DEBIAN_ARCH): multistrap.configscript
$(TAG)/multistrap-pre.$(CONFIG_DEBIAN_ARCH): $(DEBOOT)/dev/urandom
	sudo /usr/sbin/multistrap -d $(DEBOOT) --arch $(CONFIG_DEBIAN_ARCH) \
	    -f $(MULTISTRAP_CONF) >$(BUILD)/multistrap-pre.log
	$(call tag,multistrap-pre.$(CONFIG_DEBIAN_ARCH))

# multistrap-post runs the package configure scripts under emulation
$(TAG)/multistrap-post.$(CONFIG_DEBIAN_ARCH): $(TAG)/multistrap-pre.$(CONFIG_DEBIAN_ARCH)
	sudo chroot $(DEBOOT) ./multistrap.configscript >>$(BUILD)/multistrap.log
	$(call tag,multistrap-post.$(CONFIG_DEBIAN_ARCH))

# perform the debian install
$(TAG)/multistrap.$(CONFIG_DEBIAN_ARCH): $(TAG)/multistrap-pre.$(CONFIG_DEBIAN_ARCH) $(TAG)/multistrap-post.$(CONFIG_DEBIAN_ARCH)
	$(call tag,multistrap.$(CONFIG_DEBIAN_ARCH))

# TODO
# - the make targets using the ./scripts/packages.runscripts system should
#   be depending on all the packages.d/ scripts.  Need to add a auto
#   dep system to do this.

# TODO - use dpkg config to avoid installing the locale files:
# eg:
# --path-exclude=/usr/share/doc/*
# --path-include=/usr/share/doc/*/copyright

# script deps
$(TAG)/minimise.$(CONFIG_DEBIAN_ARCH): ./scripts/packages.addextra
$(TAG)/minimise.$(CONFIG_DEBIAN_ARCH): ./scripts/packages.runscripts
$(TAG)/fixup.$(CONFIG_DEBIAN_ARCH): ./scripts/packages.addextra
$(TAG)/fixup.$(CONFIG_DEBIAN_ARCH): ./scripts/packages.runscripts
$(TAG)/customise.$(CONFIG_DEBIAN_ARCH): ./scripts/packages.addextra
$(TAG)/customise.$(CONFIG_DEBIAN_ARCH): ./scripts/packages.runscripts
$(TAG)/customise.$(CONFIG_DEBIAN_ARCH): scripts/authorized_keys_local
$(TAG)/customise.$(CONFIG_DEBIAN_ARCH): scripts/authorized_keys_path

# minimise the image size
$(TAG)/minimise.$(CONFIG_DEBIAN_ARCH): $(TAG)/multistrap.$(CONFIG_DEBIAN_ARCH)
	sudo env "CONFIGDIRS=$(CONFIGDIRS)" ./scripts/packages.addextra \
	    $(DEBOOT) $(CONFIG_DEBIAN_ARCH) minimise
	sudo env "CONFIGDIRS=$(CONFIGDIRS)" ./scripts/packages.runscripts \
	    $(DEBOOT) $(CONFIG_DEBIAN_ARCH) minimise
	sudo rm -f $(DEBOOT)/multistrap.configscript $(DEBOOT)/dev/mmcblk0
	$(call tag,minimise.$(CONFIG_DEBIAN_ARCH))

# fixup the image to actually boot
$(TAG)/fixup.$(CONFIG_DEBIAN_ARCH): $(TAG)/multistrap.$(CONFIG_DEBIAN_ARCH)
	sudo env "CONFIGDIRS=$(CONFIGDIRS)" ./scripts/packages.addextra \
	    $(DEBOOT) $(CONFIG_DEBIAN_ARCH) fixup
	sudo env "CONFIGDIRS=$(CONFIGDIRS)" ./scripts/packages.runscripts \
	    $(DEBOOT) $(CONFIG_DEBIAN_ARCH) fixup
	sudo rm -f $(DEBOOT)/usr/sbin/policy-rc.d
	$(call tag,fixup.$(CONFIG_DEBIAN_ARCH))

# image customisation - setting the default config.
$(TAG)/customise.$(CONFIG_DEBIAN_ARCH): $(TAG)/multistrap.$(CONFIG_DEBIAN_ARCH)
	sudo env "CONFIGDIRS=$(CONFIGDIRS)" ./scripts/authorized_keys_local \
	    $(DEBOOT) $(CONFIG_DEBIAN_ARCH) customise
	sudo env "CONFIGDIRS=$(CONFIGDIRS)" ./scripts/authorized_keys_path \
	    $(DEBOOT) $(CONFIG_DEBIAN_ARCH) customise
	sudo env "CONFIGDIRS=$(CONFIGDIRS)" ./scripts/packages.addextra \
	    $(DEBOOT) $(CONFIG_DEBIAN_ARCH) customise
	sudo env "CONFIGDIRS=$(CONFIGDIRS)" ./scripts/packages.runscripts \
	    $(DEBOOT) $(CONFIG_DEBIAN_ARCH) customise
	echo root:$(CONFIG_ROOT_PASS) | sudo chpasswd -c SHA256 -R $(realpath $(DEBOOT))
	$(call tag,customise.$(CONFIG_DEBIAN_ARCH))

# TODO: consider what password should be default

debian: $(TAG)/debian.$(CONFIG_DEBIAN_ARCH)
$(TAG)/debian.$(CONFIG_DEBIAN_ARCH): $(TAG)/minimise.$(CONFIG_DEBIAN_ARCH) $(TAG)/fixup.$(CONFIG_DEBIAN_ARCH) $(TAG)/customise.$(CONFIG_DEBIAN_ARCH)
	$(call tag,debian.$(CONFIG_DEBIAN_ARCH))

$(BUILD)/debian.$(CONFIG_DISTRO).$(CONFIG_DEBIAN_ARCH).cpio: $(TAG)/debian.$(CONFIG_DEBIAN_ARCH)
	( \
            cd $(DEBOOT); \
            sudo find . -print0 | sudo cpio -0 -H newc -R 0:0 -o \
	) > $@

# Create a dependancy file for a given configdir
%configdir.deps: Makefile
	scripts/configdir_deps $@

CONFIGDIR_DEPS := $(addsuffix /.configdir.deps, $(CONFIGDIRS))
include $(CONFIGDIR_DEPS)

# Misc make infrastructure below here

%.lzma: %.cpio
	lzma <$< >$@

clean:
	rm -f $(MULTISTRAP_CONF) $(TAG)/* $(CONFIGDIR_DEPS)
	sudo rm -rf $(BUILD)/debian.$(CONFIG_DISTRO).*

reallyclean:
	rm -rf $(BUILD)

define tag
	@echo Touching tag $1
	@mkdir -p $(TAG)
	@touch $(TAG)/$1
endef

