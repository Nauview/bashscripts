#!/usr/bin/env bash
#
# rocky-mini-monitor.sh — Monitor básico para Rocky Linux 9
# Mide: CPU, memoria, swap, load average, discos, red y top procesos.
# Uso:
#   ./rocky-mini-monitor.sh                 # Modo interactivo (loop 5s)
#   ./rocky-mini-monitor.sh --once          # Una sola medición
#   ./rocky-mini-monitor.sh --interval 10   # Intervalo 10s (por defecto 5s)
#   ./rocky-mini-monitor.sh --count 12      # 12 iteraciones y salir
#
set -euo pipefail

INTERVAL=5
COUNT=0      # 0 = infinito
ONCE=0

log() { printf "%s\n" "$*" ; }

usage() {
  cat <<EOF
Uso: $0 [--once] [--interval SEG] [--count N]
  --once           Ejecuta una única medición y sale
  --interval SEG   Intervalo en segundos entre mediciones (default: 5)
  --count N        Número de iteraciones (0 = infinito)
EOF
}

# ---- Parseo de argumentos
while [[ $# -gt 0 ]]; do
  case "$1" in
    --once) ONCE=1; shift ;;
    --interval) INTERVAL="${2:-5}"; shift 2 ;;
    --count) COUNT="${2:-0}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) log "Opción no reconocida: $1"; usage; exit 1 ;;
  esac
done
[[ "$ONCE" -eq 1 ]] && COUNT=1

timestamp() { date +"%Y-%m-%d %H:%M:%S%z"; }
ncores() { grep -cE '^processor' /proc/cpuinfo || echo 1; }

# ---- CPU (%uso) usando /proc/stat en un delta de 1s
read_cpu() {
  # Devuelve "user nice system idle iowait irq softirq steal guest guest_nice total busy"
  local l1 l2
  read -r _ u1 n1 s1 i1 w1 q1 sq1 st1 g1 gn1 < <(grep '^cpu ' /proc/stat)
  sleep 1
  read -r _ u2 n2 s2 i2 w2 q2 sq2 st2 g2 gn2 < <(grep '^cpu ' /proc/stat)
  local idle=$(( i2 - i1 + w2 - w1 ))
  local nonidle=$(( (u2-u1) + (n2-n1) + (s2-s1) + (q2-q1) + (sq2-sq1) + (st2-st1) ))
  local total=$(( idle + nonidle ))
  local busy_pct=0
  if (( total > 0 )); then
    busy_pct=$(( 100 * nonidle / total ))
  fi
  echo "$busy_pct"
}

# ---- Memoria y Swap desde /proc/meminfo
read_mem() {
  # Resultado: "mem_used_gb mem_total_gb mem_used_pct swap_used_gb swap_total_gb swap_used_pct"
  # Leemos claves (algunas distros usan MemAvailable)
  declare -A M=()
  while read -r k v _; do M["${k%:}"]=$v; done < /proc/meminfo

  # En KiB
  local mt=${M[MemTotal]:-0}
  local ma=${M[MemAvailable]:-0}
  local mf=${M[MemFree]:-0}
  local st=${M[SwapTotal]:-0}
  local sf=${M[SwapFree]:-0}

  local mused_kib
  if (( ma > 0 )); then
    mused_kib=$(( mt - ma ))
  else
    # fallback aproximado
    mused_kib=$(( mt - mf ))
  fi
  local sused_kib=$(( st - sf ))

  # Convierte a GB con 2 decimales usando awk
  awk -v mused="$mused_kib" -v mt="$mt" -v sused="$sused_kib" -v st="$st" '
    function g(x){ return x/1024/1024 }
    BEGIN{
      mem_used_gb = g(mused)
      mem_total_gb = g(mt)
      mem_pct = (mt>0)? (100*mused/mt) : 0
      swap_used_gb = g(sused)
      swap_total_gb = g(st)
      swap_pct = (st>0)? (100*sused/st) : 0
      printf "%.2f %.2f %.0f %.2f %.2f %.0f\n", mem_used_gb, mem_total_gb, mem_pct, swap_used_gb, swap_total_gb, swap_pct
    }'
}

# ---- Load average y carga por core
read_load() {
  # Resultado: "l1 l5 l15 per_core_pct"
  read -r l1 l5 l15 _ < /proc/loadavg
  local cores; cores=$(ncores)
  awk -v l1="$l1" -v c="$cores" 'BEGIN{ per= (c>0)? (100*l1/c) : 0; printf "%.2f %.2f %.2f %.0f\n", l1, l5, l15, per }'
}

# ---- Discos: uso % y disponibilidad (df -hPT)
read_disks() {
  df -hPT -x tmpfs -x devtmpfs -x squashfs | awk 'NR==1{next} {printf "  %-18s %-6s %6s/%-6s %5s  %s\n",$7,$2,$3,$4,$6,$1}'
}

# ---- Inodos (opcional, útil en servidores con muchos archivos)
read_inodes() {
  df -i -x tmpfs -x devtmpfs -x squashfs | awk 'NR==1{next} {printf "  %-18s %7s usados  %7s libres  %5s  %s\n",$6,$3,$4,$5,$1}'
}

# ---- Red: tasa RX/TX en 1s desde /proc/net/dev
read_net() {
  # Resultado: líneas por interfaz "iface rx_kbps tx_kbps"
  declare -A R1 T1 R2 T2
  while IFS=': ' read -r iface rest; do
    [[ "$iface" == "" ]] && continue
    # campos: bytes    packets errs drop fifo frame compressed multicast | bytes ...
    rx=$(awk '{print $1}' <<< "$rest")
    tx=$(awk '{print $9}' <<< "$rest")
    R1["$iface"]=$rx; T1["$iface"]=$tx
  done < <(tail -n +3 /proc/net/dev)

  sleep 1

  while IFS=': ' read -r iface rest; do
    [[ "$iface" == "" ]] && continue
    rx=$(awk '{print $1}' <<< "$rest")
    tx=$(awk '{print $9}' <<< "$rest")
    R2["$iface"]=$rx; T2["$iface"]=$tx
  done < <(tail -n +3 /proc/net/dev)

  for i in "${!R1[@]}"; do
    # descarta interfaces down/virtuales típicas si quieres (lo dejamos simple)
    drx=$(( ${R2[$i]} - ${R1[$i]} ))
    dtx=$(( ${T2[$i]} - ${T1[$i]} ))
    # a kbps: bytes/s * 8 / 1000
    awk -v iface="$i" -v drx="$drx" -v dtx="$dtx" '
      BEGIN{
        rx_kbps = (drx>0)? (drx*8/1000) : 0
        tx_kbps = (dtx>0)? (dtx*8/1000) : 0
        printf "  %-10s RX: %8.0f kbps   TX: %8.0f kbps\n", iface, rx_kbps, tx_kbps
      }'
  done | sort
}

# ---- Sockets en LISTEN (útil para ver puertos abiertos rápidamente)
count_listen() {
  if command -v ss >/dev/null 2>&1; then
    ss -tuln | awk 'NR>1 && $1 ~ /(tcp|udp)/ {print}' | wc -l
  else
    echo 0
  fi
}

# ---- Top procesos por CPU y por MEM
top_processes() {
  echo "  CPU:"
  ps -eo pid,comm,%cpu,%mem --sort=-%cpu | awk 'NR==1{printf "    %-7s %-20s %6s %6s\n",$1,$2,$3,$4; next} NR<=6{printf "    %-7s %-20s %6s %6s\n",$1,$2,$3,$4}'
  echo "  MEM:"
  ps -eo pid,comm,%mem,%cpu --sort=-%mem | awk 'NR==1{printf "    %-7s %-20s %6s %6s\n",$1,$2,$3,$4; next} NR<=6{printf "    %-7s %-20s %6s %6s\n",$1,$2,$3,$4}'
}

print_header() {
  echo "====================================================================="
  echo "  Rocky Mini Monitor  |  $(timestamp)  |  Host: $(hostname) | Kernel: $(uname -r)"
  echo "====================================================================="
}

render() {
  print_header

  # CPU
  local cpu_busy; cpu_busy=$(read_cpu)
  printf "CPU:   uso %-3s%%\n" "$cpu_busy"

  # Memoria/Swap
  read -r mem_used mem_tot mem_pct swap_used swap_tot swap_pct < <(read_mem)
  printf "MEM:   %5.2fGB / %-5.2fGB  (%-3.0f%%)\n" "$mem_used" "$mem_tot" "$mem_pct"
  printf "SWAP:  %5.2fGB / %-5.2fGB  (%-3.0f%%)\n" "$swap_used" "$swap_tot" "$swap_pct"

  # Load
  read -r l1 l5 l15 per_core < <(read_load)
  printf "LOAD:  1m=%-4.2f  5m=%-4.2f  15m=%-4.2f   carga/CPU ≈ %-3.0f%%\n" "$l1" "$l5" "$l15" "$per_core"

  # Puertos escuchando
  local listens; listens=$(count_listen)
  printf "PORTS LISTEN: %d\n" "$listens"

  # Discos
  echo "DISKS (montaje, tipo, usado/libre, uso%, dispositivo):"
  read_disks

  # Inodos (útil en servidores con millones de ficheros)
  echo "INODES (montaje, usados, libres, uso%, dispositivo):"
  read_inodes

  # Red (tasa 1s)
  echo "NETWORK (tasa aprox. en 1s):"
  read_net

  # Top procesos
  echo "TOP PROCESSES:"
  top_processes

  echo
}

# ---- Loop principal
iter=0
while :; do
  render
  iter=$((iter+1))
  if (( COUNT > 0 && iter >= COUNT )); then
    break
  fi
  sleep "$INTERVAL"
done

