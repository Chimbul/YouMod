# Original Makefile from YTLite
DEBUG = 0
FINALPACKAGE = 1
ARCHS = arm64
TARGET := iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YouMod
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation AudioToolbox MediaPlayer
$(TWEAK_NAME)_CFLAGS = -fobjc-arc -Wno-unguarded-availability-new
$(TWEAK_NAME)_FILES = $(wildcard Files/*.x)

include $(THEOS_MAKE_PATH)/tweak.mk

# FFmpeg frameworks ride inside YouMod.bundle. They are staged after the fact
# rather than through layout/, because each binary has to be signed once it is in
# place or dlopen fails at runtime with a code-signing error.
#
# Build them first with tools/fetch-ffmpegkit.sh; the script warns and continues
# if they are absent, so a checkout without them still produces a package.
after-stage::
	@tools/stage-ffmpeg.sh "$(THEOS_STAGING_DIR)"
