#!/bin/bash
# ==========================================
# Script Migrasi Data VPN & SSH
# ==========================================

# Path lokasi database standar dari VPS Anda
SSH_DB="/etc/ssh/.ssh.db"
VMESS_DB="/etc/vmess/.vmess.db"
VLESS_DB="/etc/vless/.vless.db"
TROJAN_DB="/etc/trojan/.trojan.db"

# Nama file output akhir di server
OUTPUT_FILE="/root/data_migrasi_vps.txt"

# Mengosongkan file output jika sudah ada
> "$OUTPUT_FILE"

echo "==================================================" >> "$OUTPUT_FILE"
echo "DATA MIGRASI VPN/SSH SERVER" >> "$OUTPUT_FILE"
echo "Tanggal Ekspor: $(date +"%Y-%m-%d %H:%M:%S")" >> "$OUTPUT_FILE"
echo "==================================================" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# --- PROSES EKSPOR DATA SSH ---
echo "Ssh" >> "$OUTPUT_FILE"
printf "%-25s %-25s %-15s %-20s\n" "Username" "Password" "ip limit" "exp" >> "$OUTPUT_FILE"

if [ -f "$SSH_DB" ]; then
    while IFS= read -r line; do
        if [[ "$line" == "#ssh#"* ]]; then
            # Menghapus tag "#ssh# "
            clean_line=$(echo "$line" | sed 's/#ssh# //')

            # Memecah dan mengambil data
            username=$(echo "$clean_line" | awk '{print $1}')
            password=$(echo "$clean_line" | awk '{print $2}')
            ip_limit=$(echo "$clean_line" | awk '{print $4}')
            exp_date=$(echo "$clean_line" | awk '{print $5, $6, $7}')

            # Cetak baris data
            printf "%-25s %-25s %-15s %-20s\n" "$username" "$password" "$ip_limit" "$exp_date" >> "$OUTPUT_FILE"
        fi
    done < "$SSH_DB"
else
    echo "File database SSH ($SSH_DB) tidak ditemukan." >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

# --- FUNGSI PROSES EKSPOR DATA XRAY (VMESS, VLESS, TROJAN) ---
process_xray_data() {
    local db_file=$1
    local title=$2

    echo "$title" >> "$OUTPUT_FILE"
    printf "%-25s %-45s %-15s %-20s\n" "Username" "UUID" "quota" "exp" >> "$OUTPUT_FILE"

    if [ -f "$db_file" ]; then
        while IFS= read -r line; do
            if [[ "$line" == "###"* ]]; then
                # Menghapus tag "### "
                clean_line=$(echo "$line" | sed 's/### //')

                # Memecah dan mengambil data
                username=$(echo "$clean_line" | awk '{print $1}')
                exp_date=$(echo "$clean_line" | awk '{print $2}')
                uuid=$(echo "$clean_line" | awk '{print $3}')
                quota=$(echo "$clean_line" | awk '{print $4}')
                limit_ip=$(echo "$clean_line" | awk '{print $5}')

                # Format penulisan kuota (0 = Unlimited)
                if [[ "$quota" == "0" || -z "$quota" ]]; then
                    quota_str="Unlimited"
                else
                    quota_str="${quota} GB"
                fi

                # Cetak baris data
                printf "%-25s %-45s %-15s %-20s\n" "$username" "$uuid" "$quota_str" "$exp_date" >> "$OUTPUT_FILE"
            fi
        done < "$db_file"
    else
        echo "File database $title ($db_file) tidak ditemukan." >> "$OUTPUT_FILE"
    fi
    echo "" >> "$OUTPUT_FILE"
}

# --- JALANKAN PROSES EKSPOR ---
process_xray_data "$VMESS_DB" "vmess"
process_xray_data "$VLESS_DB" "vless"
process_xray_data "$TROJAN_DB" "trojan"

echo "=================================================="
echo "Selesai! Seluruh data user berhasil di-ekstrak."
echo "Silakan cek hasilnya dengan perintah:"
echo "cat /root/data_migrasi_vps.txt"
echo "=================================================="
