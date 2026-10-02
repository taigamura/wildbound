import { StyleSheet, View } from 'react-native';
import { StatusBar } from 'expo-status-bar';
import * as SplashScreen from 'expo-splash-screen';
import { useKeepAwake } from 'expo-keep-awake';
import GameView from './src/GameView';

SplashScreen.preventAutoHideAsync().catch(() => {});

export default function App() {
  useKeepAwake(); // don't let the screen dim mid-fight
  return (
    <View style={styles.root}>
      <StatusBar hidden />
      <GameView onReady={() => SplashScreen.hideAsync().catch(() => {})} />
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#0a0f1f' },
});
