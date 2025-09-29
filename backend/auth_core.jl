
function authenticate(username::String, password::String, ipaddr::String)
    conn = get_db_connection()
    try
        stmt = DBInterface.prepare(conn, "SELECT username, password_hash FROM users WHERE username = ?")
        result = DBInterface.execute(stmt, [username])
        
        for row in result
            if row[1] == username && row[2] == bytes2hex(sha256(password))
                jwt1 = create_jwt(username, ipaddr, 1)
                jwt2 = create_jwt(username, ipaddr, 2)
                
                expires = now() + Hour(12)
                expires_str = Dates.format(expires, dateformat"e, dd u yyyy HH:MM:SS") * " GMT"
                
                if !haskey(ACTIVE_SESSIONS, username)
                    assign_process(username)
                else
                    println("ℹ️ Session already active for $username")
                end
                
                return HTTP.Response(200, 
                    ["Set-Cookie" => "token=$(string(jwt1)); SameSite=Lax; Expires=$(expires_str)"],
                    JSON3.write(Dict("token" => string(jwt2), "username" => username)))
            end
        end
        
        println("❌ Invalid credentials")
        return HTTP.Response(401)
        
    catch e
        println("❌ Error during authentication: ", e)
        return HTTP.Response(500)
    finally
        DBInterface.close!(conn)
    end
end

function create_jwt(username, ipaddr, keyidx) 
    iat = round(Int, datetime2unix(now()))
    exp = iat + 12 * 60 * 60  # 12 hours in seconds

    conn = get_db_connection()
    is_admin_user = false
    
    try
        stmt = DBInterface.prepare(conn, "SELECT is_admin FROM users WHERE username = ?")
        result = DBInterface.execute(stmt, [username])
        
        for row in result
            is_admin_user = row[1] == 1
            break
        end
    finally
        DBInterface.close!(conn)
    end

    payload = Dict{String, Any}(
        "iss" => "seqPlayground",
        "iat" => "$iat",
        "exp" => "$exp",
        "username" => username,
        "userip" => ipaddr,
        "is_admin" => is_admin_user  # Incluir estado de administrador
    )

    jwt = JWT(; payload=payload)

    keyset_url = "$(@__DIR__)/keys/jwkkey.json"

    keyset = JWKSet("file://$keyset_url");
    refresh!(keyset)

    signingkeyset = deepcopy(keyset)
    keyids = String[]
    for k in keys(signingkeyset.keys)
        push!(keyids, k)
        signingkeyset.keys[k] = JWKRSA(signingkeyset.keys[k].kind, MbedTLS.parse_keyfile(joinpath(dirname(keyset_url), "$k.private.pem")))
    end

    keyid = keyids[keyidx]
    sign!(jwt, signingkeyset, keyid)

    return jwt
end

function get_jwt_from_cookie(cookie)
    if cookie === nothing || cookie == ""
        return nothing
    end
    # cookie es tipo String, ej: "token=abc123; other=foo"
    cookies = split(cookie, "; ")
    for c in cookies
        if startswith(c, "token=")
            return JWT(; jwt=string(split(c, "=")[2]))
        end
    end
    return nothing
end

function get_jwt_from_auth_header(auth_header)
    if auth_header === nothing || auth_header == ""
        println("→ No Authorization header found")
        return nothing
    end
    parts = split(auth_header)
    if length(parts) != 2 || lowercase(parts[1]) != "bearer"
        println("→ Authorization header format incorrect, redirecting")
        return nothing
    end
    return JWT(; jwt=string(parts[2]))
end

function check_jwt(jwt, ipaddr, keyidx)
    if jwt === nothing
        return false
    end

    keyset_url = "$(@__DIR__)/keys/jwkkey.json"

    keyset = JWKSet("file://$keyset_url");
    refresh!(keyset)

    signingkeyset = deepcopy(keyset)
    keyids = String[]
    for k in keys(signingkeyset.keys)
        push!(keyids, k)
        signingkeyset.keys[k] = JWKRSA(signingkeyset.keys[k].kind, MbedTLS.parse_keyfile(joinpath(dirname(keyset_url), "$k.private.pem")))
    end

    keyid = keyids[keyidx]

    # println("keyid: ", keyid)

    validate!(jwt, keyset, keyid)
    
    if isvalid(jwt) 
        # & (ipaddr === claims(jwt)["userip"])
        println("✅ Valid JWT $(keyidx)")
        return true
    else
        println("❌ Invalid or expired JWT $(keyidx)")
        # return HTTP.Response(303, ["Location" => "/login"])
        return false
    end
end


