// Native side of the game bridge. Mirrors game/src/core/platform.ts.
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Haptics from 'expo-haptics';

export type HapticKind = 'select' | 'light' | 'medium' | 'heavy' | 'success' | 'warning' | 'error';
export type BridgeMessage =
  | { type: 'save'; key: string; value: unknown }
  | { type: 'haptic'; kind: HapticKind }
  | { type: 'ready' };

const SAVE_KEY = 'wildbound.save.v1';
let cache: Record<string, unknown> = {};
let writeTimer: ReturnType<typeof setTimeout> | null = null;

export async function loadSave(): Promise<Record<string, unknown>> {
  try {
    const raw = await AsyncStorage.getItem(SAVE_KEY);
    cache = raw ? JSON.parse(raw) : {};
  } catch {
    cache = {};
  }
  return cache;
}

export function writeSave(key: string, value: unknown) {
  cache = { ...cache, [key]: value };
  if (writeTimer) clearTimeout(writeTimer);
  writeTimer = setTimeout(() => {
    AsyncStorage.setItem(SAVE_KEY, JSON.stringify(cache)).catch(() => {});
  }, 250);
}

export function playHaptic(kind: HapticKind) {
  switch (kind) {
    case 'select': return Haptics.selectionAsync();
    case 'light': return Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    case 'medium': return Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
    case 'heavy': return Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Heavy);
    case 'success': return Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    case 'warning': return Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning);
    case 'error': return Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
  }
}

export function parseMessage(data: string): BridgeMessage | null {
  try {
    const m = JSON.parse(data);
    return m && typeof m.type === 'string' ? (m as BridgeMessage) : null;
  } catch {
    return null;
  }
}
