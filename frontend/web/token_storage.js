(function initializeEncryptedTokenStorage(global) {
    'use strict';

    const DATABASE_NAME = 'froggy-docs-secure-storage';
    const STORE_NAME = 'encryption-keys';
    const KEY_ID = 'authorization-token-key';
    const STORAGE_KEY = 'froggy-docs.encrypted-authorization-token';

    function requestResult(request) {
        return new Promise((resolve, reject) => {
            request.onsuccess = () => resolve(request.result);
            request.onerror = () => reject(request.error);
        });
    }

    function openDatabase() {
        return new Promise((resolve, reject) => {
            const request = indexedDB.open(DATABASE_NAME, 1);
            request.onupgradeneeded = () => {
                if (!request.result.objectStoreNames.contains(STORE_NAME)) {
                    request.result.createObjectStore(STORE_NAME);
                }
            };
            request.onsuccess = () => resolve(request.result);
            request.onerror = () => reject(request.error);
        });
    }

    async function getOrCreateKey() {
        const database = await openDatabase();
        try {
            const existing = await requestResult(
                database.transaction(STORE_NAME, 'readonly').objectStore(STORE_NAME).get(KEY_ID)
            );
            if (existing) return existing;

            const key = await crypto.subtle.generateKey(
                { name: 'AES-GCM', length: 256 },
                false,
                ['encrypt', 'decrypt']
            );
            await requestResult(
                database.transaction(STORE_NAME, 'readwrite').objectStore(STORE_NAME).put(key, KEY_ID)
            );
            return key;
        } finally {
            database.close();
        }
    }

    function bytesToBase64(value) {
        return btoa(String.fromCharCode(...new Uint8Array(value)));
    }

    function base64ToBytes(value) {
        return Uint8Array.from(atob(value), character => character.charCodeAt(0));
    }

    async function save(token) {
        if (!global.crypto?.subtle || !global.indexedDB) {
            throw new Error('Encrypted browser storage is unavailable');
        }
        if (!token) {
            localStorage.removeItem(STORAGE_KEY);
            return;
        }

        const key = await getOrCreateKey();
        const iv = crypto.getRandomValues(new Uint8Array(12));
        const plaintext = new TextEncoder().encode(token);
        const encrypted = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, plaintext);
        localStorage.setItem(STORAGE_KEY, JSON.stringify({
            version: 1,
            iv: bytesToBase64(iv),
            ciphertext: bytesToBase64(encrypted),
        }));
    }

    async function load() {
        const saved = localStorage.getItem(STORAGE_KEY);
        if (!saved) return null;
        if (!global.crypto?.subtle || !global.indexedDB) {
            throw new Error('Encrypted browser storage is unavailable');
        }

        const payload = JSON.parse(saved);
        if (payload.version !== 1 || !payload.iv || !payload.ciphertext) {
            throw new Error('Stored authorization token is invalid');
        }

        const key = await getOrCreateKey();
        const decrypted = await crypto.subtle.decrypt(
            { name: 'AES-GCM', iv: base64ToBytes(payload.iv) },
            key,
            base64ToBytes(payload.ciphertext)
        );
        return new TextDecoder().decode(decrypted);
    }

    global.froggyTokenStorage = Object.freeze({ load, save });
}(window));
