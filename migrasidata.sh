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
# Kita membaca langsung dari file passwd di sistem sebagai SUMBER UTAMA
# untuk memastikan semua user SSH aktif (seperti handunSSH935 dll) terekstrak,
# terlepas apakah mereka masih ada di dalam .ssh.db atau tidak.
echo "Ssh" >> "$OUTPUT_FILE"
printf "%-25s %-25s %-15s %-20s\n" "Username" "Password" "ip limit" "exp" >> "$OUTPUT_FILE"

if [ -f "/etc/passwd" ]; then
    # Cari pengguna VPN (UID >= 1000 dan bukan 'nobody')
    awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | while IFS= read -r username; do
        
        # Ambil tanggal expired asli dari sistem Linux (chage)
        exp_date=$(chage -l "$username" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs)
        if [[ "$exp_date" == "never" || -z "$exp_date" ]]; then
            exp_date="Unlimited"
        fi
        
        # --- CARI IP LIMIT ---
        # Berdasarkan source add-ssh, IP limit aktual disimpan di /etc/kyt/limit/ssh/ip/
        ip_limit="Unknown"
        if [ -f "/etc/kyt/limit/ssh/ip/$username" ]; then
            ip_limit=$(cat "/etc/kyt/limit/ssh/ip/$username")
        fi
        if [ "$ip_limit" == "0" ]; then
            ip_limit="Unlimited"
        fi
        
        # --- CARI PASSWORD PLANETEXT ---
        password=""
        
        # Fallback 1: Cari dari database historis .ssh.db
        if [ -f "$SSH_DB" ]; then
            db_line=$(grep -w "^#ssh# ${username}" "$SSH_DB" | tail -n 1)
            if [ -n "$db_line" ]; then
                clean_db=$(echo "$db_line" | sed 's/#ssh# //')
                password=$(echo "$clean_db" | awk '{print $2}')
                
                # Jika ip_limit belum ditemukan di folder kyt, gunakan dari .db
                if [[ "$ip_limit" == "Unknown" ]]; then
                    ip_limit=$(echo "$clean_db" | awk '{print $4}')
                fi
            fi
        fi
        
        # Fallback 2: Cari dari file teks output publik (jika admin menyimpan info user di nginx)
        if [[ -z "$password" || "$password" == "Unknown(Hashed)" ]]; then
            if [ -f "/var/www/html/ssh-$username.txt" ]; then
                password=$(grep -i "Password" "/var/www/html/ssh-$username.txt" | awk -F: '{print $2}' | xargs)
            fi
        fi
        
        # Fallback 3: Gunakan hash langsung dari /etc/shadow
        if [[ -z "$password" || "$password" == "Unknown(Hashed)" ]]; then
            shadow_hash=$(awk -F: -v user="$username" '$1 == user {print $2}' /etc/shadow 2>/dev/null)
            password="${shadow_hash:-Unknown}"
        fi
        
        # Cetak baris data
        printf "%-25s %-25s %-15s %-20s\n" "$username" "$password" "$ip_limit" "$exp_date" >> "$OUTPUT_FILE"
    done
else
    echo "Gagal membaca /etc/passwd" >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

# --- FUNGSI PROSES EKSPOR DATA XRAY ---
# Kita ambil nama user & exp date dari config.json agar data yang ditarik adalah DATA AKTIF
# Namun, password/UUID, kuota, IP limit, dll ditarik dari database aktual (.db)
process_xray_config() {
    local tag=$1
    local db_file=$2
    local title=$3
    
    echo "$title" >> "$OUTPUT_FILE"
    printf "%-25s %-45s %-15s %-20s\n" "Username" "UUID" "quota" "exp" >> "$OUTPUT_FILE"
    
    if [ -f "$XRAY_CONFIG" ]; then
        # Ekstrak username dari config.json berdasarkan TAG-nya
        # Menggunakan sort -u untuk mencegah duplikat user jika ia berjalan di > 1 port (misal WS dan gRPC)
        grep -E "^[[:space:]]*${tag} " "$XRAY_CONFIG" | awk '{$1=$1;print}' | sort -u | while IFS= read -r line; do
            # Format di config.json: "TAG Username Exp_Date"
            username=$(echo "$line" | awk '{print $2}')
            
            # Default Values
            uuid="Unknown-UUID"
            quota_str="Unknown(No DB)"
            exp_date=$(echo "$line" | awk '{print $3}')
            
            # 1. Coba tarik UUID langsung dari config.json sebagai prioritas utama
            # Karena ini adalah UUID *AKTIF* yang berjalan di server saat ini
            config_uuid=$(grep -A 1 "^[[:space:]]*${tag} ${username}" "$XRAY_CONFIG" | tail -n 1 | grep -oP '(?<="id": ")[^"]+|(?<="password": ")[^"]+')
            if [ -n "$config_uuid" ]; then
                uuid="$config_uuid"
            fi
            
            # 2. Cari baris user ini di database historis (.db)
            if [ -f "$db_file" ]; then
                # Pakai pola grep yang persis mencari string username, lalu filter dengan awk agar $2 == username
                db_line=$(grep -w " ${username} " "$db_file" | awk -v user="$username" '{if($2==user) print $0}' | head -n 1)
                
                if [ -n "$db_line" ]; then
                    clean_db=$(echo "$db_line" | awk '{$1=""; print $0}' | sed 's/^ *//')
                    
                    # Sekarang formatnya: username tanggal uuid kuota limit
                    db_exp=$(echo "$clean_db" | awk '{print $2}')
                    db_uuid=$(echo "$clean_db" | awk '{print $3}')
                    db_quota=$(echo "$clean_db" | awk '{print $4}')
                    
                    # Update data jika belum dapat dari config
                    if [[ "$uuid" == "Unknown-UUID" && -n "$db_uuid" ]]; then
                        uuid="$db_uuid"
                    fi
                    
                    if [[ "$db_quota" == "0" || -z "$db_quota" ]]; then
                        quota_str="400 GB"
                    else
                        quota_str="${db_quota} GB"
                    fi
                    
                    # Update exp_date dari db jika lebih lengkap
                    if [[ -n "$db_exp" && "$db_exp" != "$exp_date" ]]; then
                        exp_date="$db_exp"
                    fi
                fi
            fi
            
            # 3. Coba cari Quota aktual dari direktori sistem utama (sumber terpercaya /etc/vmess, dll)
            # Nilai kuota di sini disimpan dalam format Byte (dikali 1024^3). Kita harus membaginya.
            if [ -f "/etc/${title}/${username}" ]; then
                real_quota_bytes=$(cat "/etc/${title}/${username}")
                if [[ "$real_quota_bytes" =~ ^[0-9]+$ && "$real_quota_bytes" -gt 0 ]]; then
                    real_quota_gb=$((real_quota_bytes / 1024 / 1024 / 1024))
                    quota_str="${real_quota_gb} GB"
                else
                    quota_str="400 GB"
                fi
            fi
            
            # 4. Fallback ke direktori limit kyt jika opsi di atas kosong/hilang
            if [[ "$quota_str" == *"Unknown"* || -z "$quota_str" || "$quota_str" == "400 GB" || "$quota_str" == "Unlimited" ]]; then
                if [ -f "/etc/kyt/limit/${title}/quota/${username}" ]; then
                    real_quota=$(cat "/etc/kyt/limit/${title}/quota/${username}")
                    if [[ "$real_quota" == "0" || -z "$real_quota" ]]; then
                        quota_str="400 GB"
                    else
                        quota_str="${real_quota} GB"
                    fi
                elif [ -f "/etc/limit/${title}/quota/${username}" ]; then
                    real_quota=$(cat "/etc/limit/${title}/quota/${username}")
                    if [[ "$real_quota" == "0" || -z "$real_quota" ]]; then
                        quota_str="400 GB"
                    else
                        quota_str="${real_quota} GB"
                    fi
                fi
            fi
            
            # Jika quota masih gagal terdeteksi (memang tidak ada limit yang diset)
            if [[ "$quota_str" == *"Unknown"* || -z "$quota_str" || "$quota_str" == "Unlimited" ]]; then
                 quota_str="400 GB" # Default fallback jika tanpa info quota
            fi
            
            printf "%-25s %-45s %-15s %-20s\n" "$username" "$uuid" "$quota_str" "$exp_date" >> "$OUTPUT_FILE"
            
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
echo "Selesai! Seluruh data user berhasil di-ekstrak."
echo "Silakan cek hasilnya dengan perintah:"
echo "cat /root/data_migrasi_vps.txt"
echo "=================================================="
