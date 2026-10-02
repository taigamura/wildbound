// Platform layer: the only place the game talks to its host.
//
// In a browser it uses localStorage and does nothing for haptics.
// Inside the iOS app (react-native-webview) it posts messages to the native shell,
// which persists saves with AsyncStorage and plays haptics with expo-haptics.
// The shell injects the saved data as window.__WB_SAVE__ before the page loads.

export type HapticKind = 'select' | 'light' | 'medium' | 'heavy' | 'success' | 'warning' | 'error';
export type BridgeMessage =
  | { type: 'save'; key: string; value: unknown }
  | { type: 'haptic'; kind: HapticKind }
  | { type: 'ready' };

declare global {
  interface Window {
    ReactNativeWebView?: { postMessage(data: string): void };
    __WB_SAVE__?: Record<string, unknown>;
  }
}

export const isNative = typeof window !== 'undefined' && !!window.ReactNativeWebView;
const post = (m: BridgeMessage) => { try { window.ReactNativeWebView?.postMessage(JSON.stringify(m)); } catch { /* host gone */ } };
const PREFIX = 'wildbound.';

export const store = {
  get<T>(key: string, fallback: T): T {
    if (isNative) {
      const v = window.__WB_SAVE__?.[key];
      return v === undefined ? fallback : (v as T);
    }
    try { const v = localStorage.getItem(PREFIX + key); return v == null ? fallback : JSON.parse(v); } catch { return fallback; }
  },
  set(key: string, value: unknown) {
    if (isNative) {
      window.__WB_SAVE__ = { ...(window.__WB_SAVE__ || {}), [key]: value };
      post({ type: 'save', key, value });
      return;
    }
    try { localStorage.setItem(PREFIX + key, JSON.stringify(value)); } catch { /* storage blocked */ }
  },
};

let lastHaptic = 0, lastWarn = 0;
export function haptic(kind: HapticKind) {
  if (!isNative) return;
  const now = performance.now();
  if (now - lastHaptic < 45 && (kind === 'light' || kind === 'select')) return; // don't spam the Taptic Engine
  if (kind === 'warning') { if (now - lastWarn < 300) return; lastWarn = now; }
  lastHaptic = now;
  post({ type: 'haptic', kind });
}

export function notifyReady() { if (isNative) post({ type: 'ready' }); }
