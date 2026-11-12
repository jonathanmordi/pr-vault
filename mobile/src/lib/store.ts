import { useSyncExternalStore } from 'react';

/** A value components can subscribe to, re-rendering when it changes. */
export class Observable<T> {
  private listeners = new Set<() => void>();

  constructor(private current: T) {}

  get value() {
    return this.current;
  }

  set value(v: T) {
    if (Object.is(v, this.current)) return;
    this.current = v;
    for (const l of this.listeners) l();
  }

  subscribe = (l: () => void) => {
    this.listeners.add(l);
    return () => {
      this.listeners.delete(l);
    };
  };

  get = () => this.current;
}

export function useObservable<T>(o: Observable<T>) {
  return useSyncExternalStore(o.subscribe, o.get);
}
