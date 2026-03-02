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
# Kita ambil list user nyata di OS yang UID-nya >= 1000 dan bukan nobody.
echo "Ssh" >> "$OUTPUT_FILE"
printf "%-25s %-25s %-15s %-20s\n" "Username" "Password" "ip limit" "exp" >> "$OUTPUT_FILE"

if [ -f "/etc/passwd" ]; then
    # Cari pengguna VPN (biasanya shell /bin/false atau id > 1000)
    awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | while IFS= read -r username; do
        # Default nilai jika tidak ada di DB
        password="Unknown(Hashed)"
        ip_limit="Unknown"
        # Ambil tanggal expired dari chage OS
        exp_date=$(chage -l "$username" 2>/dev/null | grep "Password expires" | awk -F: '{print $2}' | xargs)
        if [[ "$exp_date" == "never" || -z "$exp_date" ]]; then
            exp_date="Unlimited"
        fi

        # Coba tarik password dan limit IP aslinya dari .ssh.db bila masih tercatat
        if [ -f "$SSH_DB" ]; then
            db_line=$(grep -w "^#ssh# ${username}" "$SSH_DB" | tail -n 1)
            if [ -n "$db_line" ]; then
                clean_db=$(echo "$db_line" | sed 's/#ssh# //')
                password=$(echo "$clean_db" | awk '{print $2}')
                ip_limit=$(echo "$clean_db" | awk '{print $4}')
            fi
        fi
        
        printf "%-25s %-25s %-15s %-20s\n" "$username" "$password" "$ip_limit" "$exp_date" >> "$OUTPUT_FILE"
    done
else
    echo "Gagal membaca /etc/passwd" >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

# --- FUNGSI PROSES EKSPOR DATA XRAY ---
process_xray_config() {
    local tag=$1
    local db_file=$2
    local title=$3
    
    echo "$title" >> "$OUTPUT_FILE"
    printf "%-25s %-45s %-15s %-20s\n" "Username" "UUID" "quota" "exp" >> "$OUTPUT_FILE"
    
    if [ -f "$XRAY_CONFIG" ]; then
        # Ambil unik baris saja (karena 1 user Xray bisa dibuat di beberapa port/inbounds sehingga namanya ganda)
        grep -E "^[[:space:]]*${tag} " "$XRAY_CONFIG" | awk '{$1=$1;print}' | sort -u | while IFS= read -r line; do
            
            # Format di config.json: "TAG Username Exp_Date"
            username=$(echo "$line" | awk '{print $2}')
            exp_date=$(echo "$line" | awk '{print $3}')
            
            # Cari UUID di baris tepat di bawah baris tag username tersebut
            uuid=$(grep -A 1 "^[[:space:]]*${tag} ${username}" "$XRAY_CONFIG" | tail -n 1 | grep -oP '(?<="id": ")[^"]+|(?<="password": ")[^"]+')
            if [ -z "$uuid" ]; then
                uuid="Unknown-UUID"
            fi
            
            # Cari informasi kuota dari database mentah
            quota_str="Unlimited"
            if [ -f "$db_file" ]; then
                # Data di vmess.db / trojan.db biasanya menggunakan prefix "###" untuk semua Xray protocols (sejarah script kyt/xray db).
                # Kita gunakan pola pencarian di kolom 2:
                db_line=$(grep -w " ${username} " "$db_file" | head -n 1)
                if [ -n "$db_line" ]; then
                    # Berdasarkan feedback user: "### TrialVM117 2026-01-21 9ef4601f-... 1 1"
                    # Maka: $1 = ###, $2 = Username, $3 = ExpDate, $4 = UUID, $5 = Quota, $6 = LimitIP
                    db_quota=$(echo "$db_line" | awk '{print $5}')
                    
                    if [[ -n "$db_quota" && "$db_quota" != "0" ]]; then
                        quota_str="${db_quota} GB"
                    fi
                fi
            fi
            
            # Cetak ke output
            printf "%-25s %-45s %-15s %-20s\n" "$username" "$uuid" "$quota_str" "$exp_date" >> "$OUTPUT_FILE"
        done
    else
        echo "File konfigurasi Xray ($XRAY_CONFIG) tidak ditemukan." >> "$OUTPUT_FILE"
    fi
    echo "" >> "$OUTPUT_FILE"
}

# Tag spesifik untuk mencari user di config.json:
# (Gunakan escape string literal secara benar)
process_xray_config "###" "$VMESS_DB" "vmess"
process_xray_config "#&" "$VLESS_DB" "vless"
process_xray_config "#!" "$TROJAN_DB" "trojan"

echo "=================================================="
echo "Selesai! Seluruh data user berhasil di-ekstrak dari config aktif."
echo "Silakan cek hasilnya dengan perintah:"
echo "cat /root/data_migrasi_vps.txt"
echo "=================================================="
