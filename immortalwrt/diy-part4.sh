#!/bin/bash
#
# Modify default IP
sed -i 's/192.168.6.1/192.168.2.1/g' package/base-files/files/bin/config_generate

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

# Fix fibocom-dial: GCC 14 treats implicit function declarations as errors.
# The package calls functions across compilation units (main.c <-> QMIThread.c)
# without proper forward declarations in QMIThread.h:
#   - requestGetSIMCardNumber, requestSimBindSubscription_NAS_WMS,
#     requestSimBindSubscription_WDS_DMS_QOS (defined in QMIThread.c, used in main.c)
#   - get_private_gateway (defined in main.c, used in QMIThread.c)
# Also fix 'return ;' (return with no value) in void* thread_socket_server in main.c.
FIBOCOM_DIAL_SRC="package/community/5G-Modem-Support/fibocom-dial/src"
FIBOCOM_QMITHREAD_H="${FIBOCOM_DIAL_SRC}/QMIThread.h"
if [ -f "$FIBOCOM_QMITHREAD_H" ] && ! grep -q 'extern int requestGetSIMCardNumber' "$FIBOCOM_QMITHREAD_H"; then
  sed -i '$i extern int requestGetSIMCardNumber(PROFILE_T *profile);' "$FIBOCOM_QMITHREAD_H"
  sed -i '$i extern int requestSimBindSubscription_NAS_WMS(void);' "$FIBOCOM_QMITHREAD_H"
  sed -i '$i extern int requestSimBindSubscription_WDS_DMS_QOS(void);' "$FIBOCOM_QMITHREAD_H"
  sed -i '$i extern int get_private_gateway(char *outgateway);' "$FIBOCOM_QMITHREAD_H"
fi
if [ -f "${FIBOCOM_DIAL_SRC}/main.c" ]; then
  sed -i 's/return ;/return NULL;/g' "${FIBOCOM_DIAL_SRC}/main.c"
fi

# Fix fibocom-dial: GCC 14 rejects incompatible pointer types as hard errors in
# fibo_qmimsg_server.c. The function qmidevice_detect declares its second parameter
# as 'char **idproduct' but:
#   1. The call site passes '&getidproduct' where getidproduct is char[5], giving
#      type 'char (*)[5]' — not 'char **'.
#   2. Inside the function, 'idproduct' (char**) is passed directly to strncpy
#      which expects 'char*'.
# Fix: change the parameter to 'char *idproduct' and pass 'getidproduct' directly
# (array naturally decays to char*).
FIBOCOM_QMIMSG="${FIBOCOM_DIAL_SRC}/fibo_qmimsg_server.c"
if [ -f "$FIBOCOM_QMIMSG" ] && grep -q 'char \*\*idproduct)' "$FIBOCOM_QMIMSG"; then
  sed -i 's/char \*\*idproduct)/char *idproduct)/g' "$FIBOCOM_QMIMSG"
  sed -i 's/&getidproduct)/getidproduct)/g' "$FIBOCOM_QMIMSG"
fi

# Fix quectel_cm_5G: the upstream (inner) Makefile uses CFLAGS += -Werror which,
# combined with GCC 14's stricter warnings (e.g. -Wunused-result for unchecked
# asprintf return values in atc.c and quectel-atc-proxy.c), turns warnings into
# hard build errors.  OpenWrt passes CFLAGS as an environment variable, so the
# inner Makefile's += appends -Werror to the toolchain flags.
# Fix: override Build/Compile in the outer OpenWrt Makefile to strip -Werror from
# the downloaded source's Makefile before invoking the default compile step.
QUECTEL_OUTER_MK="package/community/5G-Modem-Support/quectel_cm_5G/Makefile"
if [ -f "$QUECTEL_OUTER_MK" ] && ! grep -q 'Werror' "$QUECTEL_OUTER_MK"; then
  # Build the multi-line Makefile block to insert before $(eval ...)
  COMPILE_BLOCK="$(printf '%s\n' \
    'define Build/Compile' \
    '	$$(SED) '"'"'s/-Werror//g'"'"' $$(PKG_BUILD_DIR)/Makefile' \
    '	$$(call Build/Compile/Default,)' \
    'endef' \
    '')"
  # Use awk to insert the block before the $(eval line (sed struggles with
  # multi-line inserts containing tabs and dollar signs).
  awk -v block="$COMPILE_BLOCK" '/\$\(eval \$\(call BuildPackage/{print block}{print}' \
    "$QUECTEL_OUTER_MK" > "${QUECTEL_OUTER_MK}.tmp" && \
    mv "${QUECTEL_OUTER_MK}.tmp" "$QUECTEL_OUTER_MK"
fi
