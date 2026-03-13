#!/bin/bash
#
# Modify default IP
sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate

# Workaround: GCC 14 + musl fortify "always_inline memset: target specific option mismatch" in mbedtls
# Root cause: When building for aarch64_cortex-a53 with GCC 14, TARGET_CFLAGS includes
# target-specific CPU flags (e.g. -mcpu=cortex-a53+crypto) that conflict with the
# always_inline memset declared in musl's fortify/string.h. GCC 14 enforces strict
# target-option consistency for always_inline functions and raises an error.
# Fix: Disable _FORTIFY_SOURCE only for mbedtls so the fortify inline is not attempted,
# resolving the mismatch without affecting any other package's compilation.
if ! grep -q '_FORTIFY_SOURCE=0' package/libs/mbedtls/Makefile; then
  if grep -q 'TARGET_CFLAGS := \$(filter-out -O%' package/libs/mbedtls/Makefile; then
    sed -i '/TARGET_CFLAGS := \$(filter-out -O%/a TARGET_CFLAGS += -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0' package/libs/mbedtls/Makefile
  else
    echo 'TARGET_CFLAGS += -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0' >> package/libs/mbedtls/Makefile
  fi
fi

# Fix mtkhqos_util Makefile: remove non-standard VERSION field that uses $(REVISION),
# which produces a version like "1-r27419-ab3b3ae26d" that is invalid for APK
# (APK requires the release suffix to be purely numeric, e.g. "1-r1").
# Removing the override lets the build system use the standard PKG_VERSION-rPKG_RELEASE format.
if [ -f package/openwrt-packages/mtkhqos_util/Makefile ]; then
  sed -i '/VERSION:=\$(PKG_RELEASE)-\$(REVISION)/d' package/openwrt-packages/mtkhqos_util/Makefile
fi

# Fix fibocom-dial: GCC 14 treats implicit function declarations as errors.
# The package calls functions across compilation units (main.c <-> QMIThread.c)
# without proper forward declarations in QMIThread.h:
#   - requestGetSIMCardNumber, requestSimBindSubscription_NAS_WMS,
#     requestSimBindSubscription_WDS_DMS_QOS (defined in QMIThread.c, used in main.c)
#   - get_private_gateway (defined in main.c, used in QMIThread.c)
# Also fix 'return ;' (return with no value) in void* thread_socket_server in main.c.
FIBOCOM_QMITHREAD_H="package/openwrt-packages/wwan/fibocom-dial/src/QMIThread.h"
if [ -f "$FIBOCOM_QMITHREAD_H" ]; then
  sed -i '$i extern int requestGetSIMCardNumber(PROFILE_T *profile);' "$FIBOCOM_QMITHREAD_H"
  sed -i '$i extern int requestSimBindSubscription_NAS_WMS(void);' "$FIBOCOM_QMITHREAD_H"
  sed -i '$i extern int requestSimBindSubscription_WDS_DMS_QOS(void);' "$FIBOCOM_QMITHREAD_H"
  sed -i '$i extern int get_private_gateway(char *outgateway);' "$FIBOCOM_QMITHREAD_H"
fi
if [ -f package/openwrt-packages/wwan/fibocom-dial/src/main.c ]; then
  sed -i 's/return ;/return NULL;/g' package/openwrt-packages/wwan/fibocom-dial/src/main.c
fi
