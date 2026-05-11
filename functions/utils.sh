#!/bin/bash

################################################################################
# INTERACTIVE INPUT & UTILITIES - testdivoip
# Funções para entrada interativa e utilitários gerais
################################################################################

################################################################################
# INTERACTIVE INPUT
################################################################################

read_input() {
    local prompt="$1"
    local default="${2:-}"
    local var_name="$3"
    
    if [ -n "$default" ]; then
        read -p "$(echo -ne ${BOLD})${prompt}${NC} [${CYAN}${default}${NC}]: " input
        input="${input:-$default}"
    else
        read -p "$(echo -ne ${BOLD})${prompt}${NC}: " input
    fi
    
    if [ -n "$var_name" ]; then
        eval "$var_name='$input'"
    else
        echo "$input"
    fi
}

read_menu() {
    local prompt="$1"
    shift
    local options=("$@")
    
    echo ""
    print_bold "$prompt"
    echo ""
    
    for i in "${!options[@]}"; do
        printf "  ${CYAN}%d)${NC} %s\n" "$((i+1))" "${options[$i]}"
    done
    
    local choice
    read -p "$(echo -ne ${BOLD})Select an option${NC} [1-${#options[@]}]: " choice
    
    if [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
        echo "$((choice-1))"
    else
        print_error "Invalid selection"
        return 1
    fi
}

read_confirmed() {
    local prompt="$1"
    local value
    
    value=$(read_input "$prompt")
    
    echo ""
    print_info "Entered: $value"
    
    local confirm
    read -p "Is this correct? [y/N]: " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "$value"
        return 0
    else
        return 1
    fi
}

read_ip() {
    local prompt="$1"
    local ip
    
    while true; do
        ip=$(read_input "$prompt")
        
        if is_valid_ip "$ip"; then
            echo "$ip"
            return 0
        else
            print_error "Invalid IP address: $ip"
        fi
    done
}

read_number() {
    local prompt="$1"
    local default="${2:-}"
    local number
    
    while true; do
        number=$(read_input "$prompt" "$default")
        
        if is_number "$number"; then
            echo "$number"
            return 0
        else
            print_error "Invalid number: $number"
        fi
    done
}

################################################################################
# CONFIGURATION MANAGEMENT
################################################################################

save_config() {
    local config_file="$1"
    shift
    declare -a config_vars=("$@")
    
    {
        echo "# testdivoip configuration"
        echo "# Generated: $(date)"
        echo ""
        
        for var in "${config_vars[@]}"; do
            local value="${!var}"
            echo "export $var='$value'"
        done
    } > "$config_file"
    
    print_success "Configuration saved to: $config_file"
}

load_config() {
    local config_file="$1"
    
    if [ -f "$config_file" ]; then
        # shellcheck source=/dev/null
        source "$config_file"
        print_success "Configuration loaded from: $config_file"
        return 0
    else
        print_warning "Configuration file not found: $config_file"
        return 1
    fi
}

################################################################################
# ARRAY FUNCTIONS
################################################################################

# Adicionar elemento a array se não existir
array_add_unique() {
    local -n arr=$1
    local element=$2
    
    for item in "${arr[@]}"; do
        if [ "$item" = "$element" ]; then
            return 1  # já existe
        fi
    done
    
    arr+=("$element")
    return 0
}

# Remover elemento de array
array_remove() {
    local -n arr=$1
    local element=$2
    
    local new_arr=()
    for item in "${arr[@]}"; do
        if [ "$item" != "$element" ]; then
            new_arr+=("$item")
        fi
    done
    
    arr=("${new_arr[@]}")
}

# Encontrar índice do elemento
array_index_of() {
    local -n arr=$1
    local element=$2
    
    for i in "${!arr[@]}"; do
        if [ "${arr[$i]}" = "$element" ]; then
            echo "$i"
            return 0
        fi
    done
    
    return 1
}

################################################################################
# FORMATTING UTILITIES
################################################################################

# Formatar número com casas decimais
format_number() {
    local number="$1"
    local decimals="${2:-2}"
    
    printf "%.${decimals}f" "$number"
}

# Converter bytes para formato legível
format_bytes() {
    local bytes="$1"
    
    if (( bytes < 1024 )); then
        echo "${bytes}B"
    elif (( bytes < 1024*1024 )); then
        echo "$((bytes/1024))KB"
    elif (( bytes < 1024*1024*1024 )); then
        echo "$((bytes/1024/1024))MB"
    else
        echo "$((bytes/1024/1024/1024))GB"
    fi
}

# Formatar tempo
format_uptime() {
    local seconds="$1"
    
    local days=$((seconds / 86400))
    local hours=$(( (seconds % 86400) / 3600 ))
    local minutes=$(( (seconds % 3600) / 60 ))
    
    if (( days > 0 )); then
        echo "${days}d ${hours}h ${minutes}m"
    elif (( hours > 0 )); then
        echo "${hours}h ${minutes}m"
    else
        echo "${minutes}m"
    fi
}

################################################################################
# PROGRESS TRACKING
################################################################################

# Simples progress bar
progress_bar() {
    local current="$1"
    local total="$2"
    local width="${3:-40}"
    
    local percentage=$((current * 100 / total))
    local filled=$((percentage * width / 100))
    
    printf "["
    printf "%${filled}s" | tr ' ' '█'
    printf "%$((width-filled))s" | tr ' ' '░'
    printf "] %d%% (%d/%d)\n" "$percentage" "$current" "$total"
}

################################################################################
# RANDOM UTILITIES
################################################################################

# Gerar ID único
generate_id() {
    local prefix="${1:-id}"
    echo "${prefix}_$(date +%s)_$$"
}

# Sleep com animação
sleep_with_animation() {
    local seconds="$1"
    local message="${2:-Waiting}"
    
    for ((i=seconds; i>0; i--)); do
        printf "\r${CYAN}${message}...${NC} $i "
        sleep 1
    done
    printf "\r%${#message}s\r" ""
}

################################################################################
# FILE UTILITIES
################################################################################

# Verificar espaço em disco
check_disk_space() {
    local path="${1:-.}"
    
    if ! check_dependency "df"; then
        return 1
    fi
    
    df -h "$path" | tail -1 | awk '{print $4}'
}

# Limpança de arquivos temporários
cleanup_old_files() {
    local directory="$1"
    local days="${2:-7}"
    
    if [ -d "$directory" ]; then
        find "$directory" -type f -mtime "+$days" -delete
        print_success "Cleaned up files older than $days days in $directory"
    fi
}

################################################################################
# SYSTEM UTILITIES
################################################################################

get_os_info() {
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        echo "$PRETTY_NAME"
    else
        echo "Unknown Linux"
    fi
}

get_kernel_version() {
    uname -r
}

get_cpu_count() {
    nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "1"
}

get_memory_total() {
    free -h | awk '/^Mem/ {print $2}'
}

get_ip_public() {
    curl -s https://ipinfo.io/ip 2>/dev/null || echo "UNKNOWN"
}

################################################################################
# TIME UTILITIES
################################################################################

get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

get_timestamp_compact() {
    date '+%Y%m%d_%H%M%S'
}

elapsed_time() {
    local start_time="$1"
    local end_time="${2:-$(date +%s)}"
    
    echo $((end_time - start_time))
}

################################################################################
# COMPARISON FUNCTIONS
################################################################################

# Comparação numérica segura
compare_float() {
    local num1="$1"
    local operator="$2"
    local num2="$3"
    
    echo "$num1 $operator $num2" | bc -l
}

# Encontrar máximo entre números
max_of() {
    printf '%s\n' "$@" | sort -nr | head -1
}

# Encontrar mínimo entre números
min_of() {
    printf '%s\n' "$@" | sort -n | head -1
}

