"""
createUser(username, password; email=nothing, full_name=nothing)

Create a new user in the system with the specified credentials.

# Arguments
- `username::String`: Unique identifier for the user in the system
- `password::String`: User's password for authentication
- 'email::String' : User's email address


# Returns
- `Response`:Server HTTP response code 

"""
function create_user(username::String, password::String, email::String)
    conn = get_db_connection()
    try
        # Verificar si usuario/email existen
        stmt = DBInterface.prepare(conn, "SELECT username, email FROM users WHERE username = ? OR email = ?")
        result = DBInterface.execute(stmt, [username, email])
        
        for row in result
            if row[1] == username
                return HTTP.Response(409, ["Content-Type" => "application/json"],
                    JSON3.write(Dict("error" => "Username already exists")))
            end
            if row[2] == email
                return HTTP.Response(409, ["Content-Type" => "application/json"],
                    JSON3.write(Dict("error" => "Email already exists")))
            end
        end
        
        # Insertar nuevo usuario
        password_hash = bytes2hex(sha256(password))
        stmt = DBInterface.prepare(conn, "INSERT INTO users (username, email, password_hash) VALUES (?, ?, ?)")
        DBInterface.execute(stmt, [username, email, password_hash])
        
        # Crear privilegios por defecto
        # user_id = DBInterface.insertid(conn)
        # stmt = DBInterface.Stmt(conn, "INSERT INTO user_privileges (user_id) VALUES (?)")
        # DBInterface.execute(stmt, [user_id])
        
        println("✅ Usuario añadido: $username")
        return HTTP.Response(201)
        
    catch e
        println("❌ Error creating user: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
                JSON3.write(Dict("error" => "Internal server error")))
    finally
        DBInterface.close!(conn)
    end
end

function assign_process(username)
    if !haskey(ACTIVE_SESSIONS, username)
        pid = get_least_used_pid()
        ACTIVE_SESSIONS[username] = pid
    else    
        println("ℹ️ Session already active for $username")
    end
end

function get_least_used_pid()
    pid_counts = Dict{Int, Int}()
    for pid in values(ACTIVE_SESSIONS)
        pid_counts[pid] = get(pid_counts, pid, 0) + 1
    end
    return argmin(pid -> get(pid_counts, pid, 0), workers())
end

"""
funcion sin uso actual

is_admin(username) 

Comprueba si un usuario tiene privilegios de administrador.

# Returns
- `Bool`: true si el usuario es administrador, false en caso contrario
"""

# function is_admin(username)
#     conn = get_db_connection()
#     try
#         stmt = DBInterface.prepare(conn, "SELECT is_admin FROM users WHERE username = ?")
#         result = DBInterface.execute(stmt, [username])
#         for row in result
#             return row[1] == 1
#         end
#         return false
#     finally
#         DBInterface.close!(conn)
#     end
# end

"""
check_admin(jwt1, jwt2)

Verifica si el usuario que hace la petición es administrador.

# Returns
- `Bool`: true si el usuario es administrador, false en caso contrario
"""
function check_admin(username)
    try
        # Consultar directamente en la base de datos (no confiar solo en el JWT)
        conn = get_db_connection()
        try
            stmt = DBInterface.prepare(conn, "SELECT is_admin FROM users WHERE username = ?")
            result = DBInterface.execute(stmt, [username])
            
            is_admin_user = false
            for row in result
                is_admin_user = row[1] == 1
                break
            end
            
            println("Usuario: $username, Es admin: $is_admin_user")
            return is_admin_user
        finally
            DBInterface.close!(conn)
        end
    catch e
        println("Error al verificar administrador: $e")
        return false
    end
end

"""
user_can_run_more_sequences(username)

Verifica si un usuario puede ejecutar más secuencias hoy según su cuota diaria.

# Returns
- `Bool`: true si puede ejecutar más secuencias
"""
function user_can_run_more_sequences(username)
    conn = get_db_connection()
    try
        # Obtener datos del usuario y sus privilegios
        query = """
        SELECT u.id, u.is_premium, COALESCE(p.max_daily_sequences, 10) as max_sequences 
        FROM users u 
        LEFT JOIN user_privileges p ON u.id = p.user_id 
        WHERE u.username = ?
        """
        
        stmt = DBInterface.prepare(conn, query)
        result = DBInterface.execute(stmt, [username])
        
        user_id = 0
        is_premium = false
        max_sequences = 10
        
        for row in result
            user_id = row[1]
            is_premium = row[2] == 1
            max_sequences = row[3]
            break
        end
        
        # Si es premium, no tiene límite
        if is_premium
            return true
        end
        
        # Verificar cuántas secuencias ha usado hoy
        query = """
        SELECT sequences_used FROM daily_sequence_usage 
        WHERE user_id = ? AND date = CURDATE()
        """
        
        stmt = DBInterface.prepare(conn, query)
        result = DBInterface.execute(stmt, [user_id])
        
        sequences_used = 0
        has_record = false
        
        for row in result
            sequences_used = row[1]
            has_record = true
            break
        end
        
        # Verificar límite y generar mensaje de log apropiado
        can_run_more = !has_record || sequences_used < max_sequences
        
        if !can_run_more
            println("🚫 LÍMITE ALCANZADO: Usuario '$username' ha alcanzado su límite diario de $max_sequences secuencias (utilizadas: $sequences_used)")
        else
            if has_record
                println("✅ Usuario '$username' puede ejecutar más secuencias (utilizadas: $sequences_used/$max_sequences)")
            else
                println("✅ Usuario '$username' ejecuta su primera secuencia del día (límite: $max_sequences)")
            end
        end
        
        return can_run_more
        
    catch e
        println("❌ Error verificando límite de secuencias: ", e)
        # En caso de error, permitimos continuar
        return true
    finally
        DBInterface.close!(conn)
    end
end

"""
register_sequence_usage(username)

Registra el uso de una secuencia por parte de un usuario en la tabla daily_sequence_usage.

# Returns
- `Bool`: true si se registró correctamente
"""
function register_sequence_usage(username)
    conn = get_db_connection()
    try
        # Obtener ID del usuario
        stmt = DBInterface.prepare(conn, "SELECT id FROM users WHERE username = ?")
        result = DBInterface.execute(stmt, [username])
        
        user_id = 0
        for row in result
            user_id = row[1]
            break
        end
        
        if user_id == 0
            println("❌ Usuario no encontrado: $username")
            return false
        end
        
        # Verificar si existe un registro para hoy
        stmt = DBInterface.prepare(conn, "SELECT id, sequences_used FROM daily_sequence_usage WHERE user_id = ? AND date = CURDATE()")
        result = DBInterface.execute(stmt, [user_id])
        
        has_record = false
        record_id = 0
        sequences_used = 0
        
        for row in result
            has_record = true
            record_id = row[1]
            sequences_used = row[2]
            break
        end
        
        if has_record
            # Actualizar registro existente
            stmt = DBInterface.prepare(conn, "UPDATE daily_sequence_usage SET sequences_used = ? WHERE id = ?")
            DBInterface.execute(stmt, [sequences_used + 1, record_id])
        else
            # Crear nuevo registro
            stmt = DBInterface.prepare(conn, "INSERT INTO daily_sequence_usage (user_id, date, sequences_used) VALUES (?, CURDATE(), 1)")
            DBInterface.execute(stmt, [user_id])
        end
        
        println("✅ Uso de secuencia registrado para usuario: $username")
        return true
        
    catch e
        println("❌ Error registrando uso de secuencia: ", e)
        return false
    finally
        DBInterface.close!(conn)
    end
end

"""
save_simulation_result(username, sequence_id, result)

Guarda el resultado de una simulación verificando las cuotas de almacenamiento.

# Returns
- `Bool`: true si se guardó correctamente
"""
function save_simulation_result(username, sequence_id, result)
    conn = get_db_connection()
    try
        # Obtener ID del usuario y sus límites
        stmt = DBInterface.prepare(conn, """
            SELECT u.id, u.is_premium, COALESCE(p.storage_quota_mb, 0.5) as storage_quota 
            FROM users u 
            LEFT JOIN user_privileges p ON u.id = p.user_id 
            WHERE u.username = ?
        """)
        result_query = DBInterface.execute(stmt, [username])
        
        user_id = 0
        is_premium = false
        storage_quota = 0.5  # Valor predeterminado en MB
        
        for row in result_query
            user_id = row[1]
            # Asegurarse que is_premium sea un booleano válido (no missing)
            is_premium = row[2] === 1 || row[2] === true
            # Asegurarse que storage_quota sea un número válido (no missing)
            storage_quota = ismissing(row[3]) ? 0.5 : row[3]
            break
        end
        
        if user_id == 0
            println("❌ Usuario no encontrado: $username")
            return false
        end
        
        # Calcular espacio actualmente utilizado
        stmt = DBInterface.prepare(conn, "SELECT SUM(file_size_mb) FROM results WHERE user_id = ?")
        result_query = DBInterface.execute(stmt, [user_id])
        
        current_usage = 0.0
        for row in result_query
            # Manejar explícitamente el caso where row[1] es missing o nothing
            if row[1] !== nothing && !ismissing(row[1])
                current_usage = row[1]
            end
            break
        end
        
        # Calcular tamaño aproximado del nuevo resultado
        # Usar sizeof para obtener el tamaño en bytes y convertirlo a MB
        new_size_mb = sizeof(result) / (1024 * 1024)
        
        # Verificar si excede la cuota (a menos que sea premium)
        # Asegurarse que todas las variables son del tipo correcto
        exceeds_quota = !is_premium && (current_usage + new_size_mb > storage_quota)
        
        if exceeds_quota
            println("❌ Excede cuota de almacenamiento: $username (Usado: $current_usage MB, Nuevo: $new_size_mb MB, Límite: $storage_quota MB)")
            return false
        end
        
        # Crear directorio si no existe
        results_dir = joinpath(@__DIR__, "..", "results")
        user_dir = joinpath(results_dir, string(user_id))
        
        # Asegurar que los directorios existan
        mkpath(results_dir)
        mkpath(user_dir)
        
        # Crear nombre de archivo con timestamp
        timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
        file_name = "$(sequence_id)_$(timestamp).dat"
        file_path = joinpath(user_dir, file_name)
        
        # Guardar resultado en disco usando write
     	open(file_path, "w") do io
    	     serialize(io, result)
	end
        
        # Obtener tamaño real del archivo
        file_size_mb = filesize(file_path) / (1024 * 1024)
        
        # Registrar en la base de datos
        stmt = DBInterface.prepare(conn, """
            INSERT INTO results (user_id, sequence_id, file_path, file_size_mb)
            VALUES (?, ?, ?, ?)
        """)
        DBInterface.execute(stmt, [user_id, string(sequence_id), file_path, file_size_mb])
        
        println("✅ Resultado guardado: $sequence_id para usuario $username (Tamaño: $(round(file_size_mb, digits=2)) MB)")
        return true
        
    catch e
        println("❌ Error guardando resultado: ", e)
        return false
    finally
        DBInterface.close!(conn)
    end
end

"""
    download_simulation_result(username::String, result_id::Int)

    Permite a un usuario descargar el archivo de un resultado de simulación si le pertenece.

    # Arguments
        - `username::String`: Nombre de usuario que solicita la descarga.
        - `result_id::Int`: ID del resultado a descargar.
    # Returns
        - `HTTP.Response`
"""
function download_simulation_result(username::String, result_id::Int)
    conn = get_db_connection()
    try
        # Verificar que el resultado pertenece al usuario
        stmt = DBInterface.prepare(conn, """
            SELECT file_path FROM results 
            WHERE id = ? AND user_id = (SELECT id FROM users WHERE username = ?)
        """)
        result_query = DBInterface.execute(stmt, [result_id, username])
        
        file_path = nothing
        for row in result_query
            file_path = row[1]
            break
        end
        
        if file_path === nothing || !isfile(file_path)
            return HTTP.Response(404, ["Content-Type" => "application/json"],
                JSON3.write(Dict("error" => "Archivo no encontrado")))
        end
        
        # Leer el archivo y enviarlo como respuesta
        file_data = read(file_path)
        headers = [
            "Content-Type" => "application/octet-stream",
            "Content-Disposition" => "attachment; filename=$(basename(file_path))"
        ]
        return HTTP.Response(200, headers, file_data)
        
    catch e
        println("❌ Error descargando resultado: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Error interno al descargar el archivo")))
    finally
        DBInterface.close!(conn)
    end
end

"""
get_user_from_jwt(req)

Extrae el nombre de usuario del JWT presente en la cookie o en el header Authorization.

# Arguments
- `req`: HTTP.Request

# Returns
- `Union{String, Nothing}`: Nombre de usuario si está autenticado, `nothing` si no.
"""
function get_user_from_jwt(req)
    # Intenta obtener el JWT de las cookies
    cookie = HTTP.header(req, "Cookie")
    jwt = get_jwt_from_cookie(cookie)
    
    # Si no hay JWT en las cookies, intenta obtenerlo del header de autorización
    if jwt === nothing
        auth_header = HTTP.header(req, "Authorization")
        if auth_header !== ""
            jwt = get_jwt_from_auth_header(auth_header)
        else
            return nothing
        end
    end
    
    try
        username = claims(jwt)["username"]
        return username
    catch
        print("no se ha encontrado el nombre de usuario")
        return nothing
    end
end

"""
get_user_results(username::String)

Obtiene todos los resultados de simulación registrados para el usuario.

# Arguments
- `username::String`: Nombre de usuario

# Returns
- `Vector{Dict}`: Lista de resultados en formato diccionario
"""
function get_user_results(username::String)
    conn = get_db_connection()
    try
        query = """
            SELECT r.id, r.sequence_id, r.created_at, r.file_size_mb
            FROM results r
            JOIN users u ON r.user_id = u.id
            WHERE u.username = ?
            ORDER BY r.created_at DESC
            LIMIT 100
        """
        stmt = DBInterface.prepare(conn, query)
        result = DBInterface.execute(stmt, [username])
        results = []
        for row in result
            push!(results, Dict(
                "id" => row[1],
                "sequence_id" => row[2],
                "created_at" => string(row[3]),
                "file_size_mb" => row[4]
            ))
        end
        return results
    catch e
        println("❌ Error obteniendo resultados del usuario: ", e)
        return []
    finally
        DBInterface.close!(conn)
    end
end
"""
get_user_info(username::String)

Obtiene toda la información de un usuario de la base de datos y la devuelve en un diccionario.

# Arguments
- `username::String`: Nombre de usuario para buscar

# Returns
- `Union{Dict{String, Any}, Nothing}`: Diccionario con la información del usuario si existe, `nothing` si no se encuentra
"""
function get_user_info(username::String)
    conn = get_db_connection()
    try
        stmt = DBInterface.prepare(conn, """
            SELECT id, username, email, password_hash, is_premium, created_at, updated_at, is_admin 
            FROM users 
            WHERE username = ?
        """)
        result = DBInterface.execute(stmt, [username])
        
        for row in result
            return Dict(
                "id" => row[1],
                "username" => row[2],
                "email" => row[3],
                "password_hash" => row[4],
                "is_premium" => row[5] == 1,
                "created_at" => string(row[6]),
                "updated_at" => string(row[7]),
                "is_admin" => row[8] == 1
            )
        end
        
        # Si no se encuentra el usuario
        return nothing
        
    catch e
        println("❌ Error obteniendo información del usuario: ", e)
        return nothing
    finally
        DBInterface.close!(conn)
    end
end
"""
get_user_privileges(username::String)

Obtiene los privilegios de un usuario de la base de datos y los devuelve en un diccionario.

# Arguments
- `username::String`: Nombre de usuario para buscar

# Returns
- `Union{Dict{String, Any}, Nothing}`: Diccionario con los privilegios del usuario si existe, `nothing` si no se encuentra
"""
function get_user_privileges(username::String)
    conn = get_db_connection()
    try
        stmt = DBInterface.prepare(conn, """
            SELECT p.gpu_access, p.max_daily_sequences, p.storage_quota_mb 
            FROM users u 
            LEFT JOIN user_privileges p ON u.id = p.user_id 
            WHERE u.username = ?
        """)
        result = DBInterface.execute(stmt, [username])
        
        for row in result
            # Usar valores por defecto si son missing
            gpu_access = ismissing(row[1]) ? false : row[1] == 1
            max_daily_sequences = ismissing(row[2]) ? 10 : row[2]
            storage_quota_mb = ismissing(row[3]) ? 0.5 : row[3]
            
            return Dict(
                "gpu_access" => gpu_access,
                "max_daily_sequences" => max_daily_sequences,
                "storage_quota_mb" => storage_quota_mb
            )
        end
        
        # Si no se encuentra el usuario
        return nothing
        
    catch e
        println("❌ Error obteniendo privilegios del usuario: ", e)
        return nothing
    finally
        DBInterface.close!(conn)
    end
end

"""
save_sequence(username, sequence_id, sequence_data)

Guarda una secuencia verificando las cuotas de almacenamiento.

# Arguments
- `username::String`: Nombre de usuario
- `sequence_id::String`: ID único de la secuencia
- `sequence_data`: Datos de la secuencia (debe ser serializable)

# Returns
- `Bool`: true si se guardó correctamente
"""
function save_sequence(username::String, sequence_id::String, sequence_data)
    conn = get_db_connection()
    try
        # Obtener ID del usuario y sus límites
        stmt = DBInterface.prepare(conn, """
            SELECT u.id, u.is_premium, COALESCE(p.storage_quota_mb, 0.5) as storage_quota 
            FROM users u 
            LEFT JOIN user_privileges p ON u.id = p.user_id 
            WHERE u.username = ?
        """)
        result_query = DBInterface.execute(stmt, [username])
        
        user_id = 0
        is_premium = false
        storage_quota = 0.5  # Valor predeterminado en MB
        
        for row in result_query
            user_id = row[1]
            is_premium = row[2] === 1 || row[2] === true
            storage_quota = ismissing(row[3]) ? 0.5 : row[3]
            break
        end
        
        if user_id == 0
            println("❌ Usuario no encontrado: $username")
            return false
        end
        
        # Calcular espacio actualmente utilizado en results
        stmt = DBInterface.prepare(conn, "SELECT SUM(file_size_mb) FROM results WHERE user_id = ?")
        result_query = DBInterface.execute(stmt, [user_id])
        
        current_usage = 0.0
        for row in result_query
            if row[1] !== nothing && !ismissing(row[1])
                current_usage = row[1]
            end
            break
        end
        
        # Calcular tamaño aproximado de la nueva secuencia
        new_size_mb = sizeof(sequence_data) / (1024 * 1024)
        
        # Verificar si excede la cuota (a menos que sea premium)
        exceeds_quota = !is_premium && (current_usage + new_size_mb > storage_quota)
        
        if exceeds_quota
            println("❌ Excede cuota de almacenamiento: $username (Usado: $current_usage MB, Nuevo: $new_size_mb MB, Límite: $storage_quota MB)")
            return false
        end
        
        # Crear directorio si no existe
        results_dir = joinpath(@__DIR__, "..", "sequences")
        user_dir = joinpath(results_dir, string(user_id))
        
        mkpath(results_dir)
        mkpath(user_dir)
        
        # Crear nombre de archivo con timestamp (agregar '_seq' para distinguir de resultados)
        timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
        file_name = "$(sequence_id).json"
        file_path = joinpath(user_dir, file_name)
        
        # Guardar secuencia en disco como JSON
        open(file_path, "w") do io
            JSON3.write(io, sequence_data)
        end
        
        # Obtener tamaño real del archivo
        file_size_mb = filesize(file_path) / (1024 * 1024)
        
        # Registrar en la base de datos en la tabla results
        stmt = DBInterface.prepare(conn, """
            INSERT INTO results (user_id, sequence_id, file_path, file_size_mb)
            VALUES (?, ?, ?, ?)
        """)
        DBInterface.execute(stmt, [user_id, sequence_id, file_path, file_size_mb])
        
        println("✅ Secuencia guardada: $sequence_id para usuario $username (Tamaño: $(round(file_size_mb, digits=2)) MB)")
        return true
        
    catch e
        println("❌ Error guardando secuencia: ", e)
        return false
    finally
        DBInterface.close!(conn)
    end
end



