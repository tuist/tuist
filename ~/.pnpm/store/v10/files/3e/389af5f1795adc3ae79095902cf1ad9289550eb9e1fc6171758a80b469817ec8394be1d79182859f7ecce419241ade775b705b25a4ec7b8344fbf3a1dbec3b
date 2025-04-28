import { toRef, isClient } from '@vueuse/shared';
import QRCode from 'qrcode';
import { ref, watch } from 'vue-demi';

function useQRCode(text, options) {
  const src = toRef(text);
  const result = ref("");
  watch(
    src,
    async (value) => {
      if (src.value && isClient)
        result.value = await QRCode.toDataURL(value, options);
    },
    { immediate: true }
  );
  return result;
}

export { useQRCode };
