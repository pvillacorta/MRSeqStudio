"""
get_all_users()

Get all users from the system with their privileges.

# Returns
- `HTTP.Response`: Users list in JSON format
"""

function get_all_users()
    conn = get_db_connection()
    try
        # Query with JOIN to get users with all their privileges
        query = """
        SELECT u.id, u.username, u.email, u.password_hash, u.is_premium, u.is_admin, u.created_at, u.updated_at,
            p.storage_quota_mb, p.gpu_access, p.max_daily_sequences
        FROM users u
        LEFT JOIN user_privileges p ON u.id = p.user_id
        """
        
        stmt = DBInterface.prepare(conn, query)
        result = DBInterface.execute(stmt)
        
        users = []
        for row in result
            # Create user object with all their privileges
            user = Dict(
                "id" => row[1],
                "username" => row[2],
                "email" => row[3],
                "is_premium" => row[5] == 1,
                "is_admin" => row[6] == 1,
                "created_at" => string(row[7]),
                "updated_at" => string(row[8]),
                "storage_quota_mb" => row[9] === nothing ? 0.5 : row[9],
                "gpu_access" => row[10] === nothing ? false : row[10] == 1,
                "max_daily_sequences" => row[11] === nothing ? 10 : row[11]
            )
            push!(users, user)
        end
        
        return HTTP.Response(200, ["Content-Type" => "application/json"],
            JSON3.write(users))
    catch e
        println("❌ Error fetching users: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Internal server error")))
    finally
        DBInterface.close!(conn)
    end
end

"""
get_user_sequence_usage(user_id)

Get the sequence usage for a specific user.

# Returns
- `HTTP.Response`: Data usage in JSON format
"""
function get_user_sequence_usage(user_id)
    conn = get_db_connection()
    try
        query = """
        SELECT date, sequences_used 
        FROM daily_sequence_usage 
        WHERE user_id = ?
        ORDER BY date DESC
        LIMIT 30
        """
        
        stmt = DBInterface.prepare(conn, query)
        result = DBInterface.execute(stmt, [user_id])
        
        usage_data = []
        for row in result
            entry = Dict(
                "date" => string(row[1]),
                "sequences_used" => row[2]
            )
            push!(usage_data, entry)
        end
        
        return HTTP.Response(200, ["Content-Type" => "application/json"],
            JSON3.write(usage_data))
    catch e
        println("❌ Error fetching sequence usage: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Internal server error")))
    finally
        DBInterface.close!(conn)
    end
end

"""
admin_create_user(user_data)

Create a new user from the admin panel.

# Arguments
- `user_data::Dict`: Data of the new user

# Returns
- `HTTP.Response`: HTTP response code
"""


function admin_create_user(user_data::Dict)
    # Access the data using exclusively strings
    username = user_data["username"]
    password = user_data["password"]
    email = user_data["email"]
    is_premium = get(user_data, "is_premium", false)
    is_admin = get(user_data, "is_admin", false)
    storage_quota_mb = get(user_data, "storage_quota_mb", 0.5)
    gpu_access = get(user_data, "gpu_access", false)
    max_daily_sequences = get(user_data, "max_daily_sequences", 10)
    
    conn = get_db_connection()
    try
        # Verify if user/email exists
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
        
        # Insert new user
        password_hash = bytes2hex(sha256(password))
        stmt = DBInterface.prepare(conn, """
            INSERT INTO users (username, email, password_hash, is_premium, is_admin, created_at, updated_at) 
            VALUES (?, ?, ?, ?, ?, NOW(), NOW())
        """)
        DBInterface.execute(stmt, [username, email, password_hash, is_premium ? 1 : 0, is_admin ? 1 : 0])
        
        # Método alternativo: Obtener el ID con una consulta
        stmt = DBInterface.prepare(conn, "SELECT id FROM users WHERE username = ?")
        result = DBInterface.execute(stmt, [username])
        user_id = 0
        for row in result
            user_id = row[1]
            break
        end
        
        # Configure storage privileges including the new fields
        stmt = DBInterface.prepare(conn, """
            INSERT INTO user_privileges (user_id, storage_quota_mb, gpu_access, max_daily_sequences) 
            VALUES (?, ?, ?, ?)
        """)
        DBInterface.execute(stmt, [user_id, storage_quota_mb, gpu_access ? 1 : 0, max_daily_sequences])
        
        println("✅ User added by admin: $username (Premium: $is_premium, Admin: $is_admin)")
        return HTTP.Response(201)
        
    catch e
        println("❌ Error creating user: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Internal server error: $e")))
    finally
        DBInterface.close!(conn)
    end
end

"""
update_user(id, user_data)

Update user data from the admin panel.

# Arguments
- `id::Int`: ID of the user to update
- `user_data::Dict`: Data to update

# Returns
- `HTTP.Response`: HTTP response code
"""
# Modify the function to use exclusively strings

function update_user(id::Int, user_data::Dict)
    conn = get_db_connection()
    try
        # Verify that the user exists
        stmt = DBInterface.prepare(conn, "SELECT id FROM users WHERE id = ?")
        result = DBInterface.execute(stmt, [id])
        found = false
        for row in result
            found = true
            break
        end
        
        if !found
            return HTTP.Response(404, ["Content-Type" => "application/json"],
                JSON3.write(Dict("error" => "User not found")))
        end
        
        # Update users table - use exclusively strings to access
        updates = String[]
        params = []
        
        if haskey(user_data, "email")
            push!(updates, "email = ?")
            push!(params, user_data["email"])
        end
        
        if haskey(user_data, "is_premium")
            push!(updates, "is_premium = ?")
            push!(params, user_data["is_premium"] ? 1 : 0)
        end
        
        if haskey(user_data, "is_admin")
            push!(updates, "is_admin = ?")
            push!(params, user_data["is_admin"] ? 1 : 0)
        end
        
        if haskey(user_data, "password")
            push!(updates, "password_hash = ?")
            push!(params, bytes2hex(sha256(user_data["password"])))
        end
        
        # Add update timestamp
        push!(updates, "updated_at = NOW()")
        
        if length(updates) > 0
            update_query = "UPDATE users SET " * join(updates, ", ") * " WHERE id = ?"
            push!(params, id)
            stmt = DBInterface.prepare(conn, update_query)
            DBInterface.execute(stmt, params)
        end
        
        # Verify if there are already privileges for this user
        stmt = DBInterface.prepare(conn, "SELECT user_id FROM user_privileges WHERE user_id = ?")
        result = DBInterface.execute(stmt, [id])
        
        privileges_exist = false
        for row in result
            privileges_exist = true
            break
        end
        
        # Update privileges
        privilege_updates = []
        privilege_params = []
        
        if haskey(user_data, "storage_quota_mb")
            push!(privilege_updates, "storage_quota_mb = ?")
            push!(privilege_params, user_data["storage_quota_mb"])
        end
        
        if haskey(user_data, "gpu_access")
            push!(privilege_updates, "gpu_access = ?")
            push!(privilege_params, user_data["gpu_access"] ? 1 : 0)
        end
        
        if haskey(user_data, "max_daily_sequences")
            push!(privilege_updates, "max_daily_sequences = ?")
            push!(privilege_params, user_data["max_daily_sequences"])
        end
        
        if length(privilege_updates) > 0
            if privileges_exist
                # Update existing privileges
                privilege_query = "UPDATE user_privileges SET " * join(privilege_updates, ", ") * " WHERE user_id = ?"
                push!(privilege_params, id)
                stmt = DBInterface.prepare(conn, privilege_query)
                DBInterface.execute(stmt, privilege_params)
            else
                # Create new privileges with default values for unspecified fields
                default_storage = haskey(user_data, "storage_quota_mb") ? user_data["storage_quota_mb"] : 0.5
                default_gpu = haskey(user_data, "gpu_access") ? (user_data["gpu_access"] ? 1 : 0) : 0
                default_max_seq = haskey(user_data, "max_daily_sequences") ? user_data["max_daily_sequences"] : 10
                
                stmt = DBInterface.prepare(conn, "INSERT INTO user_privileges (user_id, storage_quota_mb, gpu_access, max_daily_sequences) VALUES (?, ?, ?, ?)")
                DBInterface.execute(stmt, [id, default_storage, default_gpu, default_max_seq])
            end
        end
        
        println("✅ User updated: ID $id")
        return HTTP.Response(200)
        
    catch e
        println("❌ Error updating user: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Internal server error: $e")))
    finally
        DBInterface.close!(conn)
    end
end

"""
delete_user(id)

Delete a user from the system.

# Arguments
- `id::Int`: ID of the user to delete

# Returns
- `HTTP.Response`: HTTP response code
"""
function delete_user(id::Int)
    conn = get_db_connection()
    try
        # Verify that the user exists and is not an admin
        stmt = DBInterface.prepare(conn, "SELECT username, is_admin FROM users WHERE id = ?")
        result = DBInterface.execute(stmt, [id])
        
        username = nothing
        is_admin_user = false
        
        for row in result
            username = row[1]
            is_admin_user = row[2] == 1
            break
        end
        
        if username === nothing
            return HTTP.Response(404, ["Content-Type" => "application/json"],
                JSON3.write(Dict("error" => "User not found")))
        end
        
        if is_admin_user
            return HTTP.Response(403, ["Content-Type" => "application/json"],
                JSON3.write(Dict("error" => "Cannot delete an admin account")))
        end
        
        # Delete user and related data
        DBInterface.execute(conn, "START TRANSACTION")
        
        # Delete privileges
        stmt = DBInterface.prepare(conn, "DELETE FROM user_privileges WHERE user_id = ?")
        DBInterface.execute(stmt, [id])
        
        # Delete sequence usage
        stmt = DBInterface.prepare(conn, "DELETE FROM daily_sequence_usage WHERE user_id = ?")
        DBInterface.execute(stmt, [id])
        
        # Delete results
        stmt = DBInterface.prepare(conn, "DELETE FROM results WHERE user_id = ?")
        DBInterface.execute(stmt, [id])
        
        # Finally delete the user
        stmt = DBInterface.prepare(conn, "DELETE FROM users WHERE id = ?")
        DBInterface.execute(stmt, [id])
        
        DBInterface.execute(conn, "COMMIT")
        
        # Delete session if it is active
        if haskey(ACTIVE_SESSIONS, username)
            delete!(ACTIVE_SESSIONS, username)
        end
        
        println("✅ User deleted: $username (ID: $id)")
        return HTTP.Response(200)
        
    catch e
        DBInterface.execute(conn, "ROLLBACK")
        println("❌ Error deleting user: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Internal server error")))
    finally
        DBInterface.close!(conn)
    end
end

"""
get_sequence_usage_stats()

Get sequence usage statistics for all users.

# Returns
- `HTTP.Response`: Statistics in JSON format
"""
function get_sequence_usage_stats()
    conn = get_db_connection()
    try
        # Query to get daily aggregated statistics
        daily_query = """
        SELECT date, SUM(sequences_used) as total_sequences
        FROM daily_sequence_usage
        GROUP BY date
        ORDER BY date DESC
        LIMIT 30
        """
        
        # Query to get top users
        user_query = """
        SELECT u.username, SUM(d.sequences_used) as total_sequences
        FROM daily_sequence_usage d
        JOIN users u ON d.user_id = u.id
        WHERE d.date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
        GROUP BY d.user_id
        ORDER BY total_sequences DESC
        LIMIT 10
        """
        
        # Execute queries
        stmt1 = DBInterface.prepare(conn, daily_query)
        daily_result = DBInterface.execute(stmt1)
        
        stmt2 = DBInterface.prepare(conn, user_query)
        user_result = DBInterface.execute(stmt2)
        
        # Procesar resultados
        daily_stats = []
        for row in daily_result
            push!(daily_stats, Dict(
                "date" => string(row[1]),
                "total_sequences" => row[2]
            ))
        end
        
        user_stats = []
        for row in user_result
            push!(user_stats, Dict(
                "username" => row[1],
                "total_sequences" => row[2]
            ))
        end
        
        # Construir respuesta
        response = Dict(
            "daily_stats" => daily_stats,
            "top_users" => user_stats
        )
        
        return HTTP.Response(200, ["Content-Type" => "application/json"],
            JSON3.write(response))
    catch e
        println("❌ Error fetching sequence usage stats: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Internal server error")))
    finally
        DBInterface.close!(conn)
    end
end

"""
reset_user_password(id, new_password)

Change the password of a user (admin operation).

# Arguments
- `id::Int`: ID of the user
- `new_password::String`: New password

# Returns
- `HTTP.Response`: HTTP response code
"""
function reset_user_password(id::Int, new_password::String)
    conn = get_db_connection()
    try
        # Verify that the user exists
        stmt = DBInterface.prepare(conn, "SELECT id FROM users WHERE id = ?")
        result = DBInterface.execute(stmt, [id])
        
        found = false
        for row in result
            found = true
            break
        end
        
        if !found
            return HTTP.Response(404, ["Content-Type" => "application/json"],
                JSON3.write(Dict("error" => "User not found")))
        end
        
        # Update password
        password_hash = bytes2hex(sha256(new_password))
        stmt = DBInterface.prepare(conn, "UPDATE users SET password_hash = ?, updated_at = NOW() WHERE id = ?")
        DBInterface.execute(stmt, [password_hash, id])
        
        println("✅ Password reset for user ID: $id")
        return HTTP.Response(200)
        
    catch e
        println("❌ Error resetting password: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Internal server error")))
    finally
        DBInterface.close!(conn)
    end
end
"""
get_all_sequences()

Get all registered sequences.

# Returns
- `HTTP.Response`: List of sequences in JSON format
"""
function get_all_sequences()
    conn = get_db_connection()
    try
        query = """
        SELECT r.id, r.user_id, u.username, r.sequence_id, r.created_at
        FROM results r
        JOIN users u ON r.user_id = u.id
        ORDER BY r.created_at DESC
        LIMIT 1000
        """
        
        stmt = DBInterface.prepare(conn, query)
        result = DBInterface.execute(stmt)
        
        sequences = []
        for row in result
            push!(sequences, Dict(
                "id" => row[1],
                "user_id" => row[2],
                "username" => row[3],
                "sequence_id" => row[4],
                "created_at" => string(row[5])
            ))
        end
        
        return HTTP.Response(200, ["Content-Type" => "application/json"],
            JSON3.write(sequences))
    catch e
        println("❌ Error getting sequences: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Internal server error")))
    finally
        DBInterface.close!(conn)
    end
end

"""
get_user_sequences(user_id)

Get the sequences registered for a specific user.

# Returns
- `HTTP.Response`: List of sequences of the user in JSON format
"""
function get_user_sequences(user_id::Int)
    conn = get_db_connection()
    try
        query = """
        SELECT r.id, r.user_id, u.username, r.sequence_id, r.created_at
        FROM results r
        JOIN users u ON r.user_id = u.id
        WHERE r.user_id = ?
        ORDER BY r.created_at DESC
        """
        
        stmt = DBInterface.prepare(conn, query)
        result = DBInterface.execute(stmt, [user_id])
        
        sequences = []
        for row in result
            push!(sequences, Dict(
                "id" => row[1],
                "user_id" => row[2],
                "username" => row[3],
                "sequence_id" => row[4],
                "created_at" => string(row[5])
            ))
        end
        
        return HTTP.Response(200, ["Content-Type" => "application/json"],
            JSON3.write(sequences))
    catch e
        println("❌ Error getting sequences of the user: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Internal server error")))
    finally
        DBInterface.close!(conn)
    end
end

"""
get_result_details(result_id)

Get the details of a specific result.

# Returns
- `HTTP.Response`: Details of the result in JSON format
"""
function get_result_details(result_id::Int)
    conn = get_db_connection()
    try
        query = """
        SELECT r.id, r.user_id, u.username, r.sequence_id, r.file_path, 
            r.file_size_mb, r.created_at
        FROM results r
        JOIN users u ON r.user_id = u.id
        WHERE r.id = ?
        """
        
        stmt = DBInterface.prepare(conn, query)
        result = DBInterface.execute(stmt, [result_id])
        
        for row in result
            result_data = Dict(
                "id" => row[1],
                "user_id" => row[2],
                "username" => row[3],
                "sequence_id" => row[4],
                "file_path" => row[5],
                "file_size_mb" => row[6],
                "created_at" => string(row[7])
            )
            
            # Verify if the file exists
            if isfile(row[5])
                result_data["file_exists"] = true
            else
                result_data["file_exists"] = false
            end
            
            return HTTP.Response(200, ["Content-Type" => "application/json"],
                JSON3.write(result_data))
        end
        
        return HTTP.Response(404, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Result not found")))
    catch e
        println("❌ Error getting details of the result: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Internal server error")))
    finally
        DBInterface.close!(conn)
    end
end

"""
delete_result(result_id)

Delete a result and its associated file.

# Returns
- `HTTP.Response`: Confirmation of the deletion
"""
function delete_result(result_id::Int, username::String)
    if username === nothing
        return HTTP.Response(401, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "No autenticado")))
    end

    conn = get_db_connection()
    try
        # Get information of the result
        query = "SELECT user_id, file_path FROM results WHERE id = ?"
        stmt = DBInterface.prepare(conn, query)
        result = DBInterface.execute(stmt, [result_id])
        
        owner_id = nothing
        file_path = nothing
        for row in result
            owner_id = row[1]
            file_path = row[2]
            break
        end
        
        if owner_id === nothing
            return HTTP.Response(404, ["Content-Type" => "application/json"],
                JSON3.write(Dict("error" => "Result not found")))
        end

        # Get the id of the user that requests the deletion
        stmt = DBInterface.prepare(conn, "SELECT id FROM users WHERE username = ?")
        user_result = DBInterface.execute(stmt, [username])
        user_id = nothing
        for row in user_result
            user_id = row[1]
            break
        end

        # Only can delete if it is the owner or admin
        if user_id != owner_id && !is_admin
            return HTTP.Response(403, ["Content-Type" => "application/json"],
                JSON3.write(Dict("error" => "You do not have permission to delete this result")))
        end
        
        # Delete file if it exists
        if isfile(file_path)
            try
                rm(file_path)
            catch e
                println("⚠️ Could not delete the file: $file_path. Error: $e")
            end
        end
        
        # Delete record from the database
        stmt = DBInterface.prepare(conn, "DELETE FROM results WHERE id = ?")
        DBInterface.execute(stmt, [result_id])
        
        return HTTP.Response(200, ["Content-Type" => "application/json"],
            JSON3.write(Dict("message" => "Result deleted correctly")))
    catch e
        println("❌ Error deleting result: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Internal server error")))
    finally
        DBInterface.close!(conn)
    end
end

"""
get_all_sequence_usage()

Get all registered sequences.

# Returns
- `HTTP.Response`: List of sequence usage in JSON format
"""
function get_all_sequence_usage()
    conn = get_db_connection()
    try
        query = """
        SELECT d.id, d.user_id, u.username, d.date, d.sequences_used
        FROM daily_sequence_usage d
        JOIN users u ON d.user_id = u.id
        ORDER BY d.date DESC
        LIMIT 1000
        """
        
        stmt = DBInterface.prepare(conn, query)
        result = DBInterface.execute(stmt)
        
        usage_data = []
        for row in result
            push!(usage_data, Dict(
                "id" => row[1],
                "user_id" => row[2],
                "username" => row[3],
                "date" => string(row[4]),
                "sequences_used" => row[5]
            ))
        end
        
        return HTTP.Response(200, ["Content-Type" => "application/json"],
            JSON3.write(usage_data))
    catch e
        println("❌ Error getting usage data: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Internal server error")))
    finally
        DBInterface.close!(conn)
    end
end

"""
get_sequence_usage_by_id(usage_id)

Get a specific sequence usage record.

# Returns
- `HTTP.Response`: Data of the record in JSON format
"""
function get_sequence_usage_by_id(usage_id::Int)
    conn = get_db_connection()
    try
        query = """
        SELECT d.id, d.user_id, u.username, d.date, d.sequences_used
        FROM daily_sequence_usage d
        JOIN users u ON d.user_id = u.id
        WHERE d.id = ?
        """
        
        stmt = DBInterface.prepare(conn, query)
        result = DBInterface.execute(stmt, [usage_id])
        
        for row in result
            usage_data = Dict(
                "id" => row[1],
                "user_id" => row[2],
                "username" => row[3],
                "date" => string(row[4]),
                "sequences_used" => row[5]
            )
            
            return HTTP.Response(200, ["Content-Type" => "application/json"],
                JSON3.write(usage_data))
        end
        
        return HTTP.Response(404, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Record not found")))
    catch e
        println("❌ Error getting usage record: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Internal server error")))
    finally
        DBInterface.close!(conn)
    end
end

"""
update_sequence_usage(usage_id, sequences_used)

Update the number of sequences used in a record.

# Returns
- `HTTP.Response`: HTTP response code
"""
function update_sequence_usage(usage_id::Int, sequences_used::Int)
    conn = get_db_connection()
    try
        # Verify if the record exists
        stmt = DBInterface.prepare(conn, "SELECT id FROM daily_sequence_usage WHERE id = ?")
        result = DBInterface.execute(stmt, [usage_id])
        
        found = false
        for row in result
            found = true
            break
        end
        
        if !found
            return HTTP.Response(404, ["Content-Type" => "application/json"],
                JSON3.write(Dict("error" => "Record not found")))
        end
        
        # Update record
        stmt = DBInterface.prepare(conn, "UPDATE daily_sequence_usage SET sequences_used = ? WHERE id = ?")
        DBInterface.execute(stmt, [sequences_used, usage_id])
        
        return HTTP.Response(200)
    catch e
        println("❌ Error updating sequence usage: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Internal server error")))
    finally
        DBInterface.close!(conn)
    end
end
"""
get_all_results()

Get all registered simulation results.

# Returns
- `HTTP.Response`: List of results in JSON format
"""
function get_all_results()
    conn = get_db_connection()
    try
        query = """
        SELECT r.id, r.user_id, u.username, r.sequence_id, r.file_path, 
            r.file_size_mb, r.created_at
        FROM results r
        JOIN users u ON r.user_id = u.id
        ORDER BY r.created_at DESC
        LIMIT 1000
        """
        
        stmt = DBInterface.prepare(conn, query)
        result = DBInterface.execute(stmt)
        
        results_data = []
        for row in result
            result_item = Dict(
                "id" => row[1],
                "user_id" => row[2],
                "username" => row[3],
                "sequence_id" => row[4],
                "file_path" => row[5],
                "file_size_mb" => row[6],
                "created_at" => string(row[7]),
                "file_exists" => isfile(row[5])
            )
            push!(results_data, result_item)
        end
        
        return HTTP.Response(200, ["Content-Type" => "application/json"],
            JSON3.write(results_data))
    catch e
        println("❌ Error getting results: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Internal server error")))
    finally
        DBInterface.close!(conn)
    end
end


