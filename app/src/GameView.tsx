import { useCallback, useEffect, useRef, useState } from 'react';
import { StyleSheet } from 'react-native';
import { WebView, type WebViewMessageEvent } from 'react-native-webview';
import { GAME_HTML } from './game-html.generated';
import { loadSave, writeSave, playHaptic, parseMessage } from './bridge';

// Set EXPO_PUBLIC_GAME_URL (e.g. http://192.168.1.20:5173) to load the Vite dev
// server instead of the bundled build: game edits then hot-reload on the phone.
const DEV_URL = process.env.EXPO_PUBLIC_GAME_URL;

export default function GameView({ onReady }: { onReady: () => void }) {
  const [save, setSave] = useState<Record<string, unknown> | null>(null);
  const web = useRef<WebView>(null);
  const readyFired = useRef(false);

  const ready = useCallback(() => {
    if (readyFired.current) return;
    readyFired.current = true;
    onReady();
  }, [onReady]);

  useEffect(() => {
    loadSave().then(setSave);
    const t = setTimeout(ready, 4000); // never leave the splash up if the page fails
    return () => clearTimeout(t);
  }, [ready]);

  const onMessage = useCallback((e: WebViewMessageEvent) => {
    const m = parseMessage(e.nativeEvent.data);
    if (!m) return;
    if (m.type === 'save') writeSave(m.key, m.value);
    else if (m.type === 'haptic') playHaptic(m.kind)?.catch(() => {});
    else if (m.type === 'ready') ready();
  }, [ready]);

  if (!save) return null;

  // Runs before the game's own script, so platform.ts sees saved data on boot.
  const inject = `window.__WB_SAVE__ = ${JSON.stringify(save)}; true;`;

  return (
    <WebView
      ref={web}
      style={styles.web}
      source={DEV_URL ? { uri: DEV_URL } : { html: GAME_HTML, baseUrl: 'https://wildbound.local/' }}
      originWhitelist={['*']}
      injectedJavaScriptBeforeContentLoaded={inject}
      onMessage={onMessage}
      // feel like a native screen, not a web page
      scrollEnabled={false}
      bounces={false}
      overScrollMode="never"
      contentInsetAdjustmentBehavior="never"
      automaticallyAdjustContentInsets={false}
      allowsBackForwardNavigationGestures={false}
      allowsLinkPreview={false}
      textZoom={100}
      // WebAudio + no tap delay
      allowsInlineMediaPlayback
      mediaPlaybackRequiresUserAction={false}
      // iOS can kill the WebGL content process under memory pressure; come back instead of a blank screen
      onContentProcessDidTerminate={() => web.current?.reload()}
      webviewDebuggingEnabled={__DEV__}
      setSupportMultipleWindows={false}
    />
  );
}

const styles = StyleSheet.create({
  web: { flex: 1, backgroundColor: '#0a0f1f' },
});
