import 'react-native-gesture-handler/jestSetup';

jest.mock('react-native-worklets', () => require('react-native-worklets/src/mock'));
// Reanimated's mock still runs its native initializer, which throws under Jest.
jest.mock('react-native-reanimated/src/initializers', () => ({ initializeReanimatedModule: () => {} }));
jest.mock('react-native-reanimated', () => require('react-native-reanimated/mock'));

jest.mock('@react-native-async-storage/async-storage', () =>
  require('@react-native-async-storage/async-storage/jest/async-storage-mock'),
);

// The device cache is replaced with a memory store in tests.
jest.mock('expo-file-system', () => ({ File: class {}, Directory: class {}, Paths: {} }));

// Screens never reach Supabase in tests; TeamData gets a fake source.
jest.mock('@/lib/supabase', () => ({ supabase: { from: jest.fn(), rpc: jest.fn(), auth: {} } }));
