#
# A very simple test for the debian builder
#
# Builds the debian cpio and boots it in qemu with a debian installer kernel
# and modules

all: test

CONFIG_DEBIAN_VER = stretch
CONFIG_DEBIAN_ARCH = i386
export CONFIG_DEBIAN_ARCH

# added just for travisCI
CONFIG_DISABLE_KVM ?= no
ifeq ($(CONFIG_DISABLE_KVM),yes)
    QEMU_KVM=
else
    QEMU_KVM=-enable-kvm
endif

DEBIAN_KERNEL_URL = http://httpredir.debian.org/debian/dists/$(CONFIG_DEBIAN_VER)/main/installer-$(CONFIG_DEBIAN_ARCH)/current/images/netboot/debian-installer/$(CONFIG_DEBIAN_ARCH)/linux
DEBIAN_INITRD_URL = http://httpredir.debian.org/debian/dists/$(CONFIG_DEBIAN_VER)/main/installer-$(CONFIG_DEBIAN_ARCH)/current/images/netboot/debian-installer/$(CONFIG_DEBIAN_ARCH)/initrd.gz

DEBIAN_KERNEL = debian.$(CONFIG_DEBIAN_VER).$(CONFIG_DEBIAN_ARCH).kernel
DEBIAN_INITRD = debian.$(CONFIG_DEBIAN_VER).$(CONFIG_DEBIAN_ARCH).initrd.gz
DEBIAN_MODULES = debian.$(CONFIG_DEBIAN_VER).$(CONFIG_DEBIAN_ARCH).modules.cpio

$(DEBIAN_KERNEL): 
	wget -O $@ $(DEBIAN_KERNEL_URL)
	touch $@
CLEAN_FILES += $(DEBIAN_KERNEL)

$(DEBIAN_INITRD):
	wget -O $@ $(DEBIAN_INITRD_URL)
	touch $@
CLEAN_FILES += $(DEBIAN_INITRD)

$(DEBIAN_MODULES): $(DEBIAN_INITRD)
	( \
	    mkdir -p $(basename $@); \
	    cd $(basename $@); \
	    gzip -dc | cpio --make-directories -i lib/modules/*; \
	    find lib -print0 | cpio -0 -H newc -R 0:0 -o \
	) <$< >$@
CLEAN_FILES += $(DEBIAN_MODULES) $(basename $(DEBIAN_MODULES))

.FORCE:

../build/debian.stretch.i386.cpio: .FORCE
	$(MAKE) -C .. build/debian.stretch.i386.cpio

combined.initrd: $(DEBIAN_MODULES) ../build/debian.stretch.i386.cpio
	cat $^ >$@
CLEAN_FILES += combined.initrd

persistent.storage:
	truncate -s 2G $@

# Get the files ready for running a test
prepare: $(DEBIAN_KERNEL) combined.initrd persistent.storage
.PHONY: prepare

test: prepare
	qemu-system-x86_64 $(QEMU_KVM) -append console=ttyS0 \
	    -m 1024 \
	    -kernel $(DEBIAN_KERNEL) \
	    -initrd combined.initrd \
	    -netdev type=user,id=e0 -device virtio-net-pci,netdev=e0 \
	    -drive if=virtio,format=raw,file=persistent.storage \
	    -nographic

clean:
	rm -rf $(CLEAN_FILES)
