#!/bin/bash
# ==========================================
# Script Migrasi Data VPN & SSH Teraktual
# ==========================================

# Path lokasi database standar dari VPS Anda
XRAY_CONFIG="/etc/xray/config.json"
SSH_DB="/etc/ssh/.ssh.db"
VMESS_DB="/etc/vmess/.vmess.db"
VLESS_DB="/etc/vless/.vless.db"
TROJAN_DB="/etc/trojan/.trojan.db"

# Nama file output akhir di server
OUTPUT_FILE="/root/data_migrasi_vps.txt"

# Mengosongkan file output jika sudah ada
> "$OUTPUT_FILE"

echo "==================================================" >> "$OUTPUT_FILE"
echo "DATA MIGRASI VPN/SSH SERVER (DATA AKTIF)" >> "$OUTPUT_FILE"
echo "Tanggal Ekspor: $(date +"%Y-%m-%d %H:%M:%S")" >> "$OUTPUT_FILE"
echo "==================================================" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# --- PROSES EKSPOR DATA SSH ---
# Acuan utama user SSH yang masih aktif adalah /etc/passwd
echo "Ssh" >> "$OUTPUT_FILE"
printf "%-25s %-25s %-15s %-20s\n" "Username" "Password" "ip limit" "exp" >> "$OUTPUT_FILE"

if [ -f "$SSH_DB" ]; then
    while IFS= read -r line; do
        if [[ "$line" == "#ssh#"* ]]; then
            # Menghapus tag "#ssh# "
            clean_line=$(echo "$line" | sed 's/#ssh# //')

            # Memecah dan mengambil data
            username=$(echo "$clean_line" | awk '{print $1}')

            # Hanya ekstrak jika username benar-benar terdaftar aktif di OS
            if id "$username" &>/dev/null; then
                password=$(echo "$clean_line" | awk '{print $2}')
                ip_limit=$(echo "$clean_line" | awk '{print $4}')
                exp_date=$(echo "$clean_line" | awk '{print $5, $6, $7}')

                # Cetak baris data
                printf "%-25s %-25s %-15s %-20s\n" "$username" "$password" "$ip_limit" "$exp_date" >> "$OUTPUT_FILE"
            fi
        fi
    done < "$SSH_DB"
else
    echo "File database SSH ($SSH_DB) tidak ditemukan." >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

# --- FUNGSI PROSES EKSPOR DATA XRAY ---
# Agar mendapat data AKTIF seperti di menu, kita baca daftar user dari config.json
# Namun kita tarik UUID, Quota, dan Exp dari file database asli (.db)
process_xray_config() {
    local tag=$1
    local db_file=$2
    local title=$3

    echo "$title" >> "$OUTPUT_FILE"
    printf "%-25s %-45s %-15s %-20s\n" "Username" "UUID" "quota" "exp" >> "$OUTPUT_FILE"

    if [ -f "$XRAY_CONFIG" ]; then
        # Cari username yang aktif di config.json
        grep -E "^[[:space:]]*${tag} " "$XRAY_CONFIG" | while IFS= read -r line; do
            # Bersihkan spasi dan ambil username (kolom ke-2 dari tag)
            clean_line=$(echo "$line" | awk '{$1=$1;print}')
            username=$(echo "$clean_line" | awk '{print $2}')

            # Cari baris user ini di database (.db)
            # Karena vmess, vless, trojan database memakai format "### username tanggal uuid kuota limit"
            if [ -f "$db_file" ]; then
                db_line=$(grep -w "^### ${username}" "$db_file" | head -n 1)
                if [ -n "$db_line" ]; then
                    clean_db=$(echo "$db_line" | sed 's/### //')
                    exp_date=$(echo "$clean_db" | awk '{print $2}')
                    uuid=$(echo "$clean_db" | awk '{print $3}')
                    quota=$(echo "$clean_db" | awk '{print $4}')

                    if [[ "$quota" == "0" || -z "$quota" ]]; then
                        quota_str="Unlimited"
                    else
                        quota_str="${quota} GB"
                    fi

                    printf "%-25s %-45s %-15s %-20s\n" "$username" "$uuid" "$quota_str" "$exp_date" >> "$OUTPUT_FILE"
                else
                    # Jika user ada di config.json tapi tidak ada di database
                    exp_date=$(echo "$clean_line" | awk '{print $3}')
                    # Coba tarik UUID dari config.json sebagai fallback
                    uuid=$(grep -A 1 "^[[:space:]]*${tag} ${username}" "$XRAY_CONFIG" | tail -n 1 | grep -oP '(?<="id": ")[^"]+|(?<="password": ")[^"]+')
                    [ -z "$uuid" ] && uuid="Unknown-UUID"
                    printf "%-25s %-45s %-15s %-20s\n" "$username" "$uuid" "Unknown" "$exp_date" >> "$OUTPUT_FILE"
                fi
            else
                # Fallback jika file .db tidak ada
                exp_date=$(echo "$clean_line" | awk '{print $3}')
                uuid=$(grep -A 1 "^[[:space:]]*${tag} ${username}" "$XRAY_CONFIG" | tail -n 1 | grep -oP '(?<="id": ")[^"]+|(?<="password": ")[^"]+')
                [ -z "$uuid" ] && uuid="Unknown-UUID"
                printf "%-25s %-45s %-15s %-20s\n" "$username" "$uuid" "Unknown" "$exp_date" >> "$OUTPUT_FILE"
            fi

        done
    else
        echo "File konfigurasi Xray ($XRAY_CONFIG) tidak ditemukan." >> "$OUTPUT_FILE"
    fi
    echo "" >> "$OUTPUT_FILE"
}

# Tag spesifik untuk mencari user di config.json:
# VMESS  = ###
# VLESS  = #&
# TROJAN = #!
process_xray_config "###" "$VMESS_DB" "vmess"
process_xray_config "#\&" "$VLESS_DB" "vless"
process_xray_config "#\!" "$TROJAN_DB" "trojan"

echo "=================================================="
echo "Selesai! Seluruh data user berhasil di-ekstrak dari config aktif."
echo "Silakan cek hasilnya dengan perintah:"
echo "cat /root/data_migrasi_vps.txt"
echo "=================================================="
