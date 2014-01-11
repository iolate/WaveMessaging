FW_DEVICE_IP=10.0.1.3

include theos/makefiles/common.mk

TWEAK_NAME = WaveMessaging
WaveMessaging_FILES = Tweak.xm 
WaveMessaging_PRIVATE_FRAMEWORKS = XPCService
WaveMessaging_LDFLAGS = -lsubstrate

LIBRARY_NAME = libwavemessaging
libwavemessaging_FILES = libwavemessaging.mm ObjectToXPC.m
libwavemessaging_PRIVATE_FRAMEWORKS = XPCService
libwavemessaging_INSTALL_PATH = /usr/lib/

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/library.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/usr/include$(ECHO_END)
	$(ECHO_NOTHING)cp WaveMessaging.h $(THEOS_STAGING_DIR)/usr/include/WaveMessaging.h$(ECHO_END)
