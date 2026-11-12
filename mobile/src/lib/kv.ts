// Small settings saved across launches. Every call swallows storage errors:
// defaults are fine when storage is unavailable.

import AsyncStorage from '@react-native-async-storage/async-storage';

export const kv = {
  async getBool(key: string): Promise<boolean | null> {
    const v = await AsyncStorage.getItem(key);
    return v == null ? null : v === 'true';
  },

  setBool: (key: string, value: boolean) => AsyncStorage.setItem(key, String(value)),

  getString: (key: string) => AsyncStorage.getItem(key),

  setString: (key: string, value: string) => AsyncStorage.setItem(key, value),

  async getStringList(key: string): Promise<string[] | null> {
    const v = await AsyncStorage.getItem(key);
    if (v == null) return null;
    const list = JSON.parse(v);
    return Array.isArray(list) ? list : null;
  },

  setStringList: (key: string, value: string[]) => AsyncStorage.setItem(key, JSON.stringify(value)),
};
