import React, { useState, useEffect, useCallback } from 'react';
import {
  StyleSheet, Text, View, TextInput, TouchableOpacity,
  ScrollView, ActivityIndicator, SafeAreaView, Alert,
} from 'react-native';
import { StatusBar } from 'expo-status-bar';

const DEFAULT_HOST = 'http://192.168.1.10:8787';

const C = {
  bg: '#0a0e14', card: '#131a24', border: '#1f2b3a',
  text: '#e6edf3', dim: '#7d8fa3', accent: '#4ade80',
  warn: '#fbbf24', danger: '#f87171', blue: '#60a5fa',
};

function fmtBytes(b) {
  if (b === null || b === undefined) return '—';
  const u = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB'];
  let i = 0, v = b;
  while (v >= 1000 && i < u.length - 1) { v /= 1000; i++; }
  return `${v.toFixed(3)} ${u[i]}`;
}

function Card({ title, children, accent }) {
  return (
    <View style={[s.card, accent && { borderColor: accent }]}>
      {title ? <Text style={s.cardTitle}>{title}</Text> : null}
      {children}
    </View>
  );
}

function Row({ label, value, color }) {
  return (
    <View style={s.row}>
      <Text style={s.rowLabel}>{label}</Text>
      <Text style={[s.rowValue, color && { color }]}>{value}</Text>
    </View>
  );
}

export default function App() {
  const [host, setHost] = useState(DEFAULT_HOST);
  const [status, setStatus] = useState(null);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState(null);
  const [bench, setBench] = useState(null);
  const [hyperBytes, setHyperBytes] = useState('256');
  const [hyper, setHyper] = useState(null);

  const api = useCallback(async (path, opts) => {
    const r = await fetch(`${host}${path}`, opts);
    if (!r.ok && r.status !== 507) throw new Error(`HTTP ${r.status}`);
    return r.json();
  }, [host]);

  const loadStatus = useCallback(async () => {
    setLoading(true); setErr(null);
    try {
      setStatus(await api('/hram/status'));
    } catch (e) {
      setErr(`Nie mogę połączyć się z warstwą HRAM pod ${host}\n${e.message}`);
      setStatus(null);
    } finally { setLoading(false); }
  }, [api, host]);

  useEffect(() => { loadStatus(); }, [loadStatus]);

  const runBench = async () => {
    setLoading(true); setErr(null); setBench(null);
    try {
      const r = await api('/hram/bench', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ bytes: 32 * 1024 * 1024 }),
      });
      setBench(r);
    } catch (e) { setErr(`Benchmark nie powiódł się: ${e.message}`); }
    finally { setLoading(false); }
  };

  const runHyper = async () => {
    setErr(null);
    try {
      const n = parseInt(hyperBytes, 10);
      if (!Number.isFinite(n) || n < 0) throw new Error('podaj liczbę bajtów');
      setHyper(await api(`/hram/hyper?bytes=${n}`));
    } catch (e) { setErr(`Hiperprzelicznik: ${e.message}`); }
  };

  const testEnospc = async () => {
    setLoading(true); setErr(null);
    try {
      const r = await api('/hram/write', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ offset: 0, bytes: 999999999999999 }),
      });
      Alert.alert(
        r.ok ? 'Zapis się udał' : 'ENOSPC — poprawnie odrzucone',
        r.ok ? 'To nie powinno się zdarzyć.' : (r.stderr || 'brak szczegółów'),
      );
    } catch (e) { setErr(e.message); }
    finally { setLoading(false); }
  };

  return (
    <SafeAreaView style={s.root}>
      <StatusBar style="light" />
      <ScrollView contentContainerStyle={s.scroll}>

        <Text style={s.h1}>HRAM</Text>
        <Text style={s.sub}>warstwa pamięci · Kurroma-128</Text>

        {/* --- połączenie --- */}
        <Card title="Połączenie z warstwą HRAM">
          <TextInput
            style={s.input}
            value={host}
            onChangeText={setHost}
            autoCapitalize="none"
            autoCorrect={false}
            placeholder="http://IP:8787"
            placeholderTextColor={C.dim}
          />
          <TouchableOpacity style={s.btn} onPress={loadStatus}>
            <Text style={s.btnText}>Odśwież</Text>
          </TouchableOpacity>
          {loading ? <ActivityIndicator color={C.accent} style={{ marginTop: 10 }} /> : null}
        </Card>

        {err ? (
          <Card accent={C.danger}>
            <Text style={{ color: C.danger, fontSize: 13, lineHeight: 19 }}>{err}</Text>
          </Card>
        ) : null}

        {/* --- trzy liczby --- */}
        <Card title="Pojemność — trzy realne liczby">
          {status ? (
            <>
              <Row label="Zarezerwowana przestrzeń adresowa"
                   value={`${fmtBytes(status.reserved_va_bytes)}`}
                   color={C.blue} />
              <Text style={s.hint}>
                2^{status.address_bits} = {status.reserved_va_pb} PB — rezerwacja
                adresowa, nie fizyczna pamięć
              </Text>

              <View style={s.divider} />

              <Row label="Pojemność fizyczna nośnika"
                   value={fmtBytes(status.physical_bytes)} color={C.text} />
              <Row label="Realnie zapisywalne"
                   value={fmtBytes(status.writable_bytes)} color={C.accent} />
              <Row label="Plik backendu"
                   value={fmtBytes(status.backend_file_bytes)} color={C.dim} />
              <Row label="Kompresja zram"
                   value={status.zram_compression_ratio
                     ? `${status.zram_compression_ratio}×`
                     : 'niedostępna'}
                   color={status.zram_compression_ratio ? C.accent : C.dim} />
              <Text style={s.hint}>{status.note}</Text>
            </>
          ) : (
            <Text style={s.dim}>brak danych — sprawdź połączenie</Text>
          )}
        </Card>

        {/* --- benchmark --- */}
        <Card title="Benchmark zapisu (realny pomiar)">
          <TouchableOpacity style={s.btn} onPress={runBench}>
            <Text style={s.btnText}>Zapisz 32 MiB i zmierz</Text>
          </TouchableOpacity>
          {bench ? (
            <View style={{ marginTop: 12 }}>
              <Text style={s.mono}>{bench.stdout || bench.stderr}</Text>
            </View>
          ) : (
            <Text style={s.hint}>
              Pomiar wykonuje się na hoście HRAM, nie w telefonie.
            </Text>
          )}
        </Card>

        {/* --- ENOSPC --- */}
        <Card title="Test granicy nośnika">
          <TouchableOpacity style={[s.btn, { borderColor: C.warn }]} onPress={testEnospc}>
            <Text style={[s.btnText, { color: C.warn }]}>
              Spróbuj zapisać 10¹⁵ B
            </Text>
          </TouchableOpacity>
          <Text style={s.hint}>
            Oczekiwany wynik: ENOSPC. Zapis poza realny nośnik nigdy nie
            zwraca cichego zera.
          </Text>
        </Card>

        {/* --- hiperprzelicznik --- */}
        <Card title="Hiperprzelicznik 1 bit = 10¹⁵ GB" accent={C.warn}>
          <Text style={s.warnBox}>
            ⚠ ZAŁOŻENIE PROJEKTOWE — kalkulator arytmetyczny.
            To NIE jest realna pojemność pamięci.
          </Text>
          <View style={{ flexDirection: 'row', gap: 8, marginTop: 10 }}>
            <TextInput
              style={[s.input, { flex: 1 }]}
              value={hyperBytes}
              onChangeText={setHyperBytes}
              keyboardType="numeric"
              placeholder="bajty"
              placeholderTextColor={C.dim}
            />
            <TouchableOpacity style={[s.btn, { flex: 0, paddingHorizontal: 18 }]}
                              onPress={runHyper}>
              <Text style={s.btnText}>Licz</Text>
            </TouchableOpacity>
          </View>

          {hyper ? (
            <View style={{ marginTop: 12 }}>
              <Row label="Wejście" value={`${hyper.input_bytes} B = ${hyper.input_bits} bitów`} />
              <View style={s.divider} />
              <Row label="GB" value={hyper.GB.toExponential(4)} color={C.warn} />
              <Row label="TB" value={hyper.TB.toExponential(4)} color={C.warn} />
              <Row label="PB" value={hyper.PB.toExponential(4)} color={C.warn} />
              <Row label="EB" value={hyper.EB.toExponential(4)} color={C.warn} />
              <Row label="ZB" value={hyper.ZB.toExponential(4)} color={C.warn} />
              <Row label="YB" value={hyper.YB.toExponential(4)} color={C.warn} />
              <View style={s.divider} />
              <Row label="Razem w bajtach" value={hyper.total_bytes.toExponential(4)} />
              <Row label="Potrzeba bitów adresu"
                   value={`${hyper.address_bits_needed}`} color={C.danger} />
              <Text style={[s.hint, { color: C.danger, marginTop: 8 }]}>
                {hyper.verdict}
              </Text>
              <View style={s.divider} />
              <Text style={s.hint}>Realne limity sprzętu:</Text>
              <Row label="ARM64 48-bit" value={hyper.reference_limits.ARM64_48bit} />
              <Row label="x86-64 57-bit" value={hyper.reference_limits.x86_64_57bit} />
              <Row label="Kurroma-128 50-bit"
                   value={hyper.reference_limits.Kurroma_128_50bit} />
            </View>
          ) : null}
        </Card>

        <Text style={s.footer}>
          Aplikacja nie zawiera logiki pamięci — tylko łączy się z API HRAM.
        </Text>
      </ScrollView>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: C.bg },
  scroll: { padding: 16, paddingBottom: 40 },
  h1: { color: C.text, fontSize: 34, fontWeight: '800', letterSpacing: 2 },
  sub: { color: C.dim, fontSize: 13, marginBottom: 18, marginTop: 2 },
  card: {
    backgroundColor: C.card, borderRadius: 14, padding: 16,
    marginBottom: 14, borderWidth: 1, borderColor: C.border,
  },
  cardTitle: {
    color: C.text, fontSize: 14, fontWeight: '700',
    marginBottom: 12, letterSpacing: 0.3,
  },
  row: {
    flexDirection: 'row', justifyContent: 'space-between',
    alignItems: 'flex-start', paddingVertical: 5, gap: 12,
  },
  rowLabel: { color: C.dim, fontSize: 12.5, flex: 1 },
  rowValue: { color: C.text, fontSize: 13, fontWeight: '600', textAlign: 'right' },
  divider: { height: 1, backgroundColor: C.border, marginVertical: 10 },
  hint: { color: C.dim, fontSize: 11.5, lineHeight: 17, marginTop: 6 },
  input: {
    backgroundColor: '#0d131b', borderWidth: 1, borderColor: C.border,
    borderRadius: 9, paddingHorizontal: 12, paddingVertical: 10,
    color: C.text, fontSize: 13,
  },
  btn: {
    marginTop: 10, borderWidth: 1, borderColor: C.accent,
    borderRadius: 9, paddingVertical: 11, alignItems: 'center',
  },
  btnText: { color: C.accent, fontSize: 13, fontWeight: '700' },
  mono: {
    color: C.text, fontSize: 11, fontFamily: 'monospace',
    lineHeight: 17, backgroundColor: '#0d131b', padding: 10, borderRadius: 8,
  },
  warnBox: {
    color: C.warn, fontSize: 11.5, lineHeight: 17,
    backgroundColor: 'rgba(251,191,36,0.08)', padding: 10, borderRadius: 8,
  },
  dim: { color: C.dim, fontSize: 12 },
  footer: {
    color: C.dim, fontSize: 11, textAlign: 'center',
    marginTop: 8, lineHeight: 16,
  },
});
