TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard

# 根目录平铺版：编译前自动生成 Theos 需要的 layout 结构
before-all::
	@mkdir -p layout/DEBIAN
	@mkdir -p layout/Library/MobileSubstrate/DynamicLibraries
	@cp control layout/DEBIAN/control
	@cp LyricBubble.plist layout/Library/MobileSubstrate/DynamicLibraries/LyricBubble.plist

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LyricBubble
LyricBubble_FILES = Tweak.x
LyricBubble_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
LyricBubble_FRAMEWORKS = UIKit Foundation
LyricBubble_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/tweak.mk
