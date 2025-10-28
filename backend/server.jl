using Distributed

if nprocs() == 1
   addprocs(5)
end

@everywhere begin
   cd(@__DIR__)
   using Pkg
   Pkg.activate(".")
   Pkg.instantiate()
end

using Oxygen
using HTTP
using TOML
using MySQL
using DBInterface
using SwaggerMarkdown
using SHA
using JWTs, MbedTLS
using Serialization

using StatsBase, FFTW
using StructTypes

@everywhere begin
   using KomaMRI
   using LinearAlgebra
   using JSON3
   using Dates
   using CUDA
end

dynamic_files_path = string(@__DIR__, "/../frontend/dist")
phantom_files_path = string(@__DIR__, "/phantoms")

dynamicfiles(dynamic_files_path, "/") 
staticfiles(phantom_files_path, "/public")

const PUBLIC_URLS = ["/login", "/login.js", "/login.js.map", "/register"]
const PRIVATE_URLS = ["/simulate", "/recon", "/plot_sequence", "/plot_phantom"]
const ADMIN_URLS = ["/admin", "/api/admin/users", "/api/admin/sequences", "/api/admin/sequences/{userId}", "/api/admin/results/{resultId}", "/api/admin/stats/sequences", "/api/admin/users/{userId}/sequences"]

const AUTH_FILE  = "auth.txt"
const USERS_FILE = "users.txt"

global simID = 1
# Dictionaries whose key is the simulation ID
global SIM_METADATA     = Dict{Int, Any}()
global SIM_PROGRESSES   = Dict{Int, Int}()
global RECON_PROGRESSES = Dict{Int, Int}()
global STATUS_FILES     = Dict{Int, String}()
# Dictionaries whose key is the username
global RAW_RESULTS      = Dict{String, Any}()
global RECON_RESULTS    = Dict{String, Any}()
global PHANTOMS         = Dict{String, Phantom}()   
global SEQUENCES        = Dict{String, Sequence}()   
global SCANNERS         = Dict{String, Scanner}()
global ROT_MATRICES     = Dict{String, Matrix}() 
global ACTIVE_SESSIONS  = Dict{String, Int}()

# ------------------------------ FUNCTIONS ------------------------------------

@everywhere begin
   ##No cambiar los includes de orden
   include("db_core.jl")
   include("auth_core.jl")
   include("users_core.jl")
   include("sequences_core.jl")
   include("api_utils.jl")
   include("mri_utils.jl")
   include("admin_db.jl")
   
   """Updates simulation progress and writes it in a file."""
   function KomaMRICore.update_blink_window_progress!(w::String, block, Nblocks)
      progress = trunc(Int, block / Nblocks * 100)
      update_progress!(w, progress)
      return nothing
   end

   function update_progress!(w::String, progress::Int)
      io = open(w,"w")
      write(io,progress)
      close(io)
   end
end

# Función auxiliar para normalizar claves de diccionarios y objetos JSON3
function normalize_keys(obj)
    # Convertir JSON3.Object a Dict si es necesario
    if obj isa JSON3.Object
        dict = Dict(pairs(obj))
    else
        dict = obj
    end
    
    # Verificar que sea un diccionario
    if !(dict isa Dict)
        return obj  # Si no es Dict ni JSON3.Object, devolver sin cambios
    end
    
    # Convertir símbolos a strings (siempre)
    return Dict(String(k) => (v isa Dict || v isa JSON3.Object ? normalize_keys(v) : v) 
               for (k, v) in pairs(dict))
end

## AUTHENTICATION
function AuthMiddleware(handler)
   return function(req::HTTP.Request)
      println("Auth middleware")
      path = String(req.target)
      jwt1 = get_jwt_from_cookie(HTTP.header(req, "Cookie"))
      jwt2 = get_jwt_from_auth_header(HTTP.header(req, "Authorization"))
      ipaddr = string(HTTP.header(req, "X-Forwarded-For", "127.0.0.1"))
      if path in ADMIN_URLS
      # Admin resource. This requires both the cookie and the Authorization header, as well as admin permissions
         if (check_jwt(jwt1, ipaddr, 1) && check_jwt(jwt2, ipaddr, 2))
            username = claims(jwt1)["username"]
            is_admin_user = check_admin(username)
            if is_admin_user
               println("✅ User $username is an admin")
               handler(req)
            else
               println("❌ User $username is not an admin, access denied")
               return HTTP.Response(403, ["Content-Type" => "text/html"],
                  """
                  <html>
                  <head><title>Access Denied</title></head>
                  <body>
                        <h1>Access Denied</h1>
                        <p>You do not have admin permissions to access this page.</p>
                        <p><a href="/app">Back to the application</a></p>
                  </body>
                  </html>
                  """)
            end
         else
            return HTTP.Response(303, ["Location" => "/login"])
         end
      elseif (path in PUBLIC_URLS) 
      # Public resource. This does not requires cookie
         return check_jwt(jwt1, ipaddr, 1) ? HTTP.Response(303, ["Location" => "/app"]) : handler(req)
      elseif any(base -> startswith(path, base), PRIVATE_URLS) 
      # Private resource. This requires both the cookie and the Authorization header
         return (check_jwt(jwt1, ipaddr, 1) && check_jwt(jwt2, ipaddr, 2)) ? handler(req) : HTTP.Response(303, ["Location" => "/login"])
      else 
      # Private dashboard. This only requires the cookie.
         return check_jwt(jwt1, ipaddr, 1) ? handler(req) : HTTP.Response(303, ["Location" => "/login"])
      end
   end
end

# ---------------------------- API METHODS ---------------------------------
@swagger """
/login:
   get:
      tags:
      - users
      summary: Get the login page
      description: Returns the login HTML page.
      responses:
         '200':
            description: Login HTML page
            content:
              text/html:
                schema:
                  format: html
         '404':
            description: Not found
         '500':
            description: Internal server error
   post:
      tags:
      - users
      summary: Authenticate user and start session
      description: Authenticates a user and starts a session, returning a JWT token in a cookie.
      requestBody:
         required: true
         content:
            application/json:
               schema:
                  type: object
                  properties:
                     username:
                        type: string
                     password:
                        type: string
                  required:
                     - username
                     - password
      responses:
         '200':
            description: Login successful, JWT token set in cookie
         '401':
            description: Invalid credentials
         '500':
            description: Internal server error
"""
@get "/login" function(req::HTTP.Request) 
   return render_html(dynamic_files_path * "/login.html")
end

@post "/login" function(req::HTTP.Request) 
   input_data = normalize_keys(json(req))
   ipaddr     = string(HTTP.header(req, "X-Forwarded-For", "127.0.0.1"))
   return authenticate(input_data["username"], input_data["password"], ipaddr)
end

@swagger """
/register:
   get:
      tags:
      - users
      summary: Get the registration page
      description: Returns the registration HTML page.
      responses:
         '200':
            description: Registration HTML page
            content:
              text/html:
                schema:
                  format: html
         '404':
            description: Not found
         '500':
            description: Internal server error
   post:
      tags:
      - users
      summary: Register a new user
      description: Registers a new user with username, password, and email.
      requestBody:
         required: true
         content:
            application/json:
               schema:
                  type: object
                  properties:
                     username:
                        type: string
                     password:
                        type: string
                     email:
                        type: string
                  required:
                     - username
                     - password
                     - email
      responses:
         '201':
            description: User created successfully
         '400':
            description: Invalid input or user already exists
         '500':
            description: Internal server error
"""
@get "/register" function(req::HTTP.Request) 
   return render_html(dynamic_files_path * "/register.html")
end

@post "/register" function(req::HTTP.Request) 
   input_data = normalize_keys(json(req))
   return create_user(input_data["username"], input_data["password"], input_data["email"])
end

@swagger """
/logout:
   get:
      tags:
      - users
      summary: Logout user
      description: Logs out the current user and invalidates the session.
      responses:
         '200':
            description: Logout successful, JWT cookie cleared
            headers:
               Set-Cookie:
                  description: JWT token cookie cleared
                  schema:
                     type: string
         '401':
            description: Not authenticated
         '500':
            description: Internal server error
"""
@get "/logout" function(req::HTTP.Request) 
   jwt1 = get_jwt_from_cookie(HTTP.header(req, "Cookie"))
   username = claims(jwt1)["username"]
   delete!(ACTIVE_SESSIONS, username)

   expires = now()
   expires_str = Dates.format(expires, dateformat"e, dd u yyyy HH:MM:SS") * " GMT"
   delete!(ACTIVE_SESSIONS, username)
   return HTTP.Response(200, ["Set-Cookie" => "token=null; SameSite=Lax; Expires=$(expires_str)"])
end

@swagger """
/app:
   get:
      tags:
      - gui
      summary: Get the app and the web content
      description: Get the app and the web content
      responses:
         '200':
            description: App and web content
            content:
              text/html:
                schema:
                  format: html
         '404':
            description: Not found
         '500':
            description: Internal server error
"""
@get "/app" function(req::HTTP.Request)
   return render_html(dynamic_files_path * "/index.html")
end

## SIMULATION
@swagger """
/simulate:
   post:
      tags:
      - simulation
      summary: Add a new simulation request
      description: Add a new simulation request
      requestBody:
         required: true
         content:
            application/json:
               schema:
                  type: object
                  properties:
                     sequence:
                        type: object
                     scanner:
                        type: object
               example:
                  sequence: {
                     "blocks": [
                        {
                              "children": [],
                              "cod": 1,
                              "duration": 1e-3,
                              "gradients": [
                                 {
                                    "amplitude": 1e-3,
                                    "axis": "x",
                                    "delay": 0,
                                    "flatTop": 1e-3,
                                    "rise": 5e-4
                                 },
                                 {
                                    "amplitude": 0,
                                    "axis": "y",
                                    "delay": 0,
                                    "flatTop": 0,
                                    "rise": 0
                                 },
                                 {
                                    "amplitude": 0,
                                    "axis": "z",
                                    "delay": 0,
                                    "flatTop": 0,
                                    "rise": 0
                                 }
                              ],
                              "name": "",
                              "ngroups": 0,
                              "rf": [
                                 {
                                    "deltaf": 0,
                                    "flipAngle": 10,
                                    "shape": 0
                                 }
                              ]
                        },
                        {
                           "adcDelay": 0,
                           "adcPhase": 0,
                           "children": [],
                           "cod": 4,
                           "duration": 1e-3,
                           "gradients": [
                              {
                                 "amplitude": 1e-3,
                                 "axis": "x",
                                 "delay": 0,
                                 "flatTop": 1e-3,
                                 "rise": 5e-4
                              },
                              {
                                 "amplitude": 0,
                                 "axis": "y",
                                 "delay": 0,
                                 "flatTop": 0,
                                 "rise": 0
                              },
                              {
                                 "amplitude": 0,
                                 "axis": "z",
                                 "delay": 0,
                                 "flatTop": 0,
                                 "rise": 0
                              }
                           ],
                           "name": "",
                           "ngroups": 0,
                           "samples": 64
                        }
                     ],
                     "description": "Simple RF pulse and ADC sequence",
                  }
                  scanner: {
                     "parameters": {
                        "b0": 1.5,
                        "b1": 10e-6,
                        "deltat": 2e-6,
                        "gmax": 60e-3,
                        "smax": 500
                     },
                  }
      responses:
         '202':
            description: Accepted operation
            headers:
              Location:
                description: URL with the simulation ID, to check the status of the simulation
                schema:
                  type: string
                  format: uri
         '400':
            description: Invalid input
         '500':
            description: Internal server error
"""
@post "/simulate" function(req::HTTP.Request)
   # Get user information
   jwt2 = get_jwt_from_auth_header(HTTP.header(req, "Authorization"))
   uname = claims(jwt2)["username"]
   
   # Verify if the user can run more sequences today
   if !user_can_run_more_sequences(uname)
         println("⛔ ACCESS DENIED: The simulation request for '$uname' has been rejected because it exceeded the daily limit")
      return HTTP.Response(403, ["Content-Type" => "application/json"],
         JSON3.write(Dict("error" => "You have reached your daily sequence limit")))
   end
   pid = ACTIVE_SESSIONS[uname]
   # Configurar archivo de estado temporal
   STATUS_FILES[simID] = tempname()
   touch(STATUS_FILES[simID])

   scanner_json   = json(req)["scanner"]
   sequence_json  = json(req)["sequence"]
   SCANNERS[uname]                       = json_to_scanner(scanner_json)
   SEQUENCES[uname], ROT_MATRICES[uname] = json_to_sequence(sequence_json, SCANNERS[uname])
   
   ########### movidas de secuencias y gestion de users
   # Generate a unique ID for the sequence
   sequence_unique_id = "seq_$(now())_$(rand(1:10000))"
   
   # Save simulation metadata
   SIM_METADATA[simID] = Dict(
      "uname" => uname,
      "sequence_id" => sequence_unique_id,
      "start_time" => now()
   )

   # Register sequence usage
   register_sequence_usage(uname)
   save_sequence(uname, sequence_unique_id, SEQUENCES[uname])
   #Check the privileges for the gpu usage
   user_privs = get_user_privileges(uname)
   gpu_active = false
   if user_privs === nothing
      println("[!!!] Could not get the privileges for $uname")
   else
      gpu_active = user_privs["gpu_access"]
   end
   ################ fin de movidas

   if !haskey(ACTIVE_SESSIONS, uname) # Check if the user has already an active session
      assign_process(uname) # We assign a new julia process to the user
   end
   # Simulation  (asynchronous. It should not block the HTTP 202 Response)
   RAW_RESULTS[uname]                    = @spawnat pid sim(PHANTOMS[uname], SEQUENCES[uname], SCANNERS[uname], STATUS_FILES[simID], gpu_active)

   headers = ["Location" => string("/simulate/",simID)]
   global simID += 1
   # 202: Partial Content
   return HTTP.Response(202,headers)
end

@swagger """
/simulate/{simID}:
   get:
      tags:
      - simulation
      summary: Get the result of a simulation
      description: Get the result of a simulation. If the simulation has finished, it returns its result. If not, it returns 303 with location = /simulate/{simID}/status
      parameters:
         - in: path
           name: simID
           required: true
           description: The ID of the simulation
           schema:
              type: integer
              example: 1
         - in: query
           name: width
           description: Width of the image
           schema:
              type: integer
              example: 800
         - in: query 
           name: height
           description: Height of the image
           schema:
              type: integer
              example: 600
      responses:
         '200':
            description: Simulation result
            content:
              text/html:
                schema:
                  format: html
         '303':
            description: Simulation not finished yet
            headers:
              Location:
                description: URL with the simulation status
                schema:
                  type: string
                  format: uri
         '404':
            description: Simulation not found
         '500':
            description: Internal server error
"""
@get "/simulate/{simID}" function(req::HTTP.Request, simID, width::Int, height::Int)
   jwt2 = get_jwt_from_auth_header(HTTP.header(req, "Authorization"))
   uname = claims(jwt2)["username"]
   _simID = parse(Int, simID)
   io = open(STATUS_FILES[_simID],"r")
   SIM_PROGRESSES[_simID] = -1 # Initialize simulation progress
   if (!eof(io))
      SIM_PROGRESSES[_simID] = read(io,Int32)
   end
   close(io)
   if -2 < SIM_PROGRESSES[_simID] < 100      # Simulation not started or in progress
      headers = ["Location" => string("/simulate/",_simID,"/status")]
      return HTTP.Response(303,headers)
   elseif SIM_PROGRESSES[_simID] == 100  # Simulation finished
      width  = width  - 15
      height = height - 20
      sig = fetch(RAW_RESULTS[uname])  
      p = plot_signal(sig; darkmode=true, width=width, height=height, slider=height>275)
      html_buffer = IOBuffer()
      KomaMRIPlots.PlotlyBase.to_html(html_buffer, p.plot)

      ################ MOVIDAS DE GESTION ###############
      # Only save the result if it has not been saved previously
      if haskey(SIM_METADATA, _simID) && !haskey(SIM_METADATA[_simID], "saved")
         metadata = SIM_METADATA[_simID]
         sequence_id = metadata["sequence_id"]

         
         
         # Try to save the result (check internally the space limits)
         save_result = save_simulation_result(uname, sequence_id, sig)
         
         # Mark as saved to avoid repeated attempts
         SIM_METADATA[_simID]["saved"] = save_result
         if !save_result
            println("⚠️ Could not save the result because it exceeded the storage quota")
         end
      end
      ###################### MOVIDAS DE GESTION ##################
      return HTTP.Response(200,body=take!(html_buffer))
   elseif SIM_PROGRESSES[_simID] == -2 # Simulation failed
      return HTTP.Response(500,body=JSON3.write("Simulation failed"))
   end
end

@swagger """
/simulate/{simID}/status:
   get:
      tags:
      - simulation
      summary: Get the status of a simulation
      description: |
         Get the status of a simulation:
         - If the simulation has not started yet, it returns -1
         - If the simulation has has failed, it returns -2
         - If the simulation is running, it returns a value between 0 and 100
         - If the simulation has finished but the reconstruction is in progress, it returns 100
         - If the reconstruction has finished, it returns 101
      parameters:
         - in: path
           name: simID
           required: true
           description: The ID of the simulation
           schema:
              type: integer
              example: 1
      responses:
         '200':
            description: Simulation status
            content:
              application/json:
                schema:
                  type: object
                  properties:
                     progress:
                        type: integer
                        description: Simulation progress
         '404':
            description: Simulation not found
         '500':
            description: Internal server error
"""
@get "/simulate/{simID}/status" function(req::HTTP.Request, simID)
   return HTTP.Response(200,body=JSON3.write(SIM_PROGRESSES[parse(Int, simID)]))
end

## RECONSTRUCTION
@swagger """
/recon/{simID}:
   post:
      tags:
      - reconstruction
      summary: Start reconstruction for a completed simulation
      description: Start reconstruction for a previously completed simulation using the existing simulation data
      parameters:
         - in: path
           name: simID
           required: true
           description: The ID of the completed simulation to reconstruct
           schema:
              type: integer
              example: 1
      responses:
         '202':
            description: Accepted operation
            headers:
              Location:
                description: URL with the reconstruction ID, to check the status of the reconstruction
                schema:
                  type: string
                  format: uri
         '400':
            description: Invalid input (no simulation data or simulation not complete)
         '500':
            description: Internal server error
"""
@post "/recon/{simID}" function(req::HTTP.Request, simID)
   jwt2 = get_jwt_from_auth_header(HTTP.header(req, "Authorization"))
   uname = claims(jwt2)["username"]
   _simID = parse(Int, simID)

   if !haskey(ACTIVE_SESSIONS, uname) # Check if the user has already an active session
      assign_process(uname) # We assign a new julia process to the user
   end

   pid = ACTIVE_SESSIONS[uname]

   # Check if we have simulation data for this user
   if !haskey(RAW_RESULTS, uname)
      return HTTP.Response(400, body="No simulation data available for reconstruction")
   end

   # Check if simulation is complete by checking if we can fetch the result
   try
      fetch(RAW_RESULTS[uname])
   catch
      return HTTP.Response(400, body="Simulation not yet complete")
   end
   
   RECON_RESULTS[uname] = @spawnat pid recon(fetch(RAW_RESULTS[uname]), SEQUENCES[uname], ROT_MATRICES[uname], STATUS_FILES[_simID])
   
   headers = ["Location" => string("/recon/",_simID)]
   # 202: Accepted
   return HTTP.Response(202,headers)
end


@get "/recon/{simID}" function(req::HTTP.Request, simID, width::Int, height::Int)
   jwt2 = get_jwt_from_auth_header(HTTP.header(req, "Authorization"))
   uname = claims(jwt2)["username"]
   _simID = parse(Int, simID)
   io = open(STATUS_FILES[_simID],"r")
   RECON_PROGRESSES[_simID] = -1 # Initialize reconstruction progress
   if (!eof(io))
      RECON_PROGRESSES[_simID] = read(io,Int32)
   end
   close(io)
   if RECON_PROGRESSES[_simID] == 100 # Reconstruction not finished
      headers = ["Location" => string("/recon/",_simID,"/status")]
      return HTTP.Response(303,headers)
   elseif RECON_PROGRESSES[_simID] == 101 # Reconstruction finished
      img    = fetch(RECON_RESULTS[uname])[1]
      kspace = fetch(RECON_RESULTS[uname])[2]
      width  = width  - 15
      height = height - 20
      p_img    = plot_image(abs.(img[:,:,1]);    darkmode=true, width=width, height=height)
      p_kspace = plot_image(abs.(kspace[:,:,1]); darkmode=true, width=width, height=height, zmax=percentile(vec(abs.(kspace[:,:,1])), 99))
      
      # Create separate HTML buffers
      img_buffer = IOBuffer()
      kspace_buffer = IOBuffer()
      KomaMRIPlots.PlotlyBase.to_html(img_buffer, p_img.plot)
      KomaMRIPlots.PlotlyBase.to_html(kspace_buffer, p_kspace.plot)
      
      # Get the HTML content
      img_html = String(take!(img_buffer))
      kspace_html = String(take!(kspace_buffer))
      
      # Return as JSON
      result = Dict(
          "image_html" => img_html,
          "kspace_html" => kspace_html
      )
      
      return HTTP.Response(200, body=JSON3.write(result))
   else
      return HTTP.Response(404, body="Simulation not found")
   end
end

@get "/recon/{simID}/status" function(req::HTTP.Request, simID)
   return HTTP.Response(200,body=JSON3.write(RECON_PROGRESSES[parse(Int, simID)]))
end

## PLOT SEQUENCE
@swagger """
/plot_sequence:
   post:
      tags:
      - plot
      summary: Plot a sequence
      description: Plot a sequence
      requestBody:
         required: true
         content:
            application/json:
               schema:
                  type: object
                  properties:
                     scanner:
                        type: object
                     sequence:
                        type: object
                     width:
                        type: integer
                     height:
                        type: integer
               example:
                  scanner: {
                     "parameters": {
                        "b0": 1.5,
                        "b1": 10e-6,
                        "deltat": 2e-6,
                        "gmax": 60e-3,
                        "smax": 500
                     },
                  }
                  sequence: {
                     "blocks": [
                        {
                              "children": [],
                              "cod": 1,
                              "duration": 1e-3,
                              "gradients": [
                                 {
                                    "amplitude": 1e-3,
                                    "axis": "x",
                                    "delay": 0,
                                    "flatTop": 1e-3,
                                    "rise": 5e-4
                                 },
                                 {
                                    "amplitude": 0,
                                    "axis": "y",
                                    "delay": 0,
                                    "flatTop": 0,
                                    "rise": 0
                                 },
                                 {
                                    "amplitude": 0,
                                    "axis": "z",
                                    "delay": 0,
                                    "flatTop": 0,
                                    "rise": 0
                                 }
                              ],
                              "name": "",
                              "ngroups": 0,
                              "rf": [
                                 {
                                    "deltaf": 0,
                                    "flipAngle": 10,
                                    "shape": 0
                                 }
                              ]
                        },
                        {
                           "adcDelay": 0,
                           "adcPhase": 0,
                           "children": [],
                           "cod": 4,
                           "duration": 1e-3,
                           "gradients": [
                              {
                                 "amplitude": 1e-3,
                                 "axis": "x",
                                 "delay": 0,
                                 "flatTop": 1e-3,
                                 "rise": 5e-4
                              },
                              {
                                 "amplitude": 0,
                                 "axis": "y",
                                 "delay": 0,
                                 "flatTop": 0,
                                 "rise": 0
                              },
                              {
                                 "amplitude": 0,
                                 "axis": "z",
                                 "delay": 0,
                                 "flatTop": 0,
                                 "rise": 0
                              }
                           ],
                           "name": "",
                           "ngroups": 0,
                           "samples": 64
                        }
                     ],
                     "description": "Simple RF pulse and ADC sequence",
                  }
                  width: 800
                  height: 600
      responses: 
         '200':
            description: Plot of the sequence
            content:
              text/html:
                schema:
                  format: html
         '400':
            description: Invalid input
         '500':
            description: Internal server error
"""
@post "/plot_sequence" function(req::HTTP.Request)
   try
      scanner_data = json(req)["scanner"]
      seq_data     = json(req)["sequence"]
      width  = json(req)["width"]  - 15
      height = json(req)["height"] - 20
      jwt2 = get_jwt_from_auth_header(HTTP.header(req, "Authorization"))
      uname = claims(jwt2)["username"]

      if !haskey(ACTIVE_SESSIONS, uname) # Check if the user has already an active session
         assign_process(uname) # Assign a new Julia process to the user
      end
      pid = ACTIVE_SESSIONS[uname]

      SCANNERS[uname]                       = json_to_scanner(scanner_data)
      SEQUENCES[uname], ROT_MATRICES[uname] = json_to_sequence(seq_data, SCANNERS[uname])

      p_seq    = remotecall_fetch(plot_seq, pid, SEQUENCES[uname]; darkmode=true, width=width, height=height, slider=height>275)
      p_kspace = remotecall_fetch(plot_kspace, pid, SEQUENCES[uname]; darkmode=true, width=width, height=height)

      seq_buffer = IOBuffer()
      kspace_buffer = IOBuffer()
      KomaMRIPlots.PlotlyBase.to_html(seq_buffer, p_seq.plot)
      KomaMRIPlots.PlotlyBase.to_html(kspace_buffer, p_kspace.plot)

      seq_html = String(take!(seq_buffer))
      kspace_html = String(take!(kspace_buffer))

      result = Dict(
          "seq_html" => seq_html,
          "kspace_html" => kspace_html
      )

      return HTTP.Response(200,body=JSON3.write(result))
   catch e
      println(e)
      return HTTP.Response(500,body=JSON3.write(string(e)))
   end
end

## SELECT AND PLOT PHANTOM
@swagger """
/plot_phantom:
   post:
      tags:
      - plot
      summary: Initialize and plot the selected phantom for the user
      description: >
         This endpoint is called from the frontend every time the user changes the "Phantom" field in the interface.
         It initializes the user's phantom in the backend according to the selected value and returns an HTML response with an interactive plot of the selected phantom.
         The plot corresponds to the selected map (e.g., PD, T1, T2, Δw) and is sized according to the provided width and height.
         The user must be authenticated (requires Authorization header with JWT).
      requestBody:
         required: true
         content:
            application/json:
               schema:
                  type: object
                  properties:
                     phantom:
                        type: string
                        description: Name of the phantom to initialize (e.g., "brain2D", "aorta3D", etc.)
                     map:
                        type: string
                        description: Map to plot ("PD", "T1", "T2", "dw", etc.)
                     width:
                        type: integer
                        description: Plot width in pixels
                     height:
                        type: integer
                        description: Plot height in pixels
               example:
                  phantom: "brain2D"
                  map: "PD"
                  width: 800
                  height: 600
      responses: 
         '200':
            description: Interactive HTML plot of the selected phantom
            content:
              text/html:
                schema:
                  format: html
         '400':
            description: Invalid input
         '401':
            description: Unauthorized (missing or invalid JWT)
         '500':
            description: Internal server error
"""
@post "/plot_phantom" function(req::HTTP.Request)
   try
      input_data = json(req)
      phantom_string = input_data["phantom"]
      map_str = input_data["map"]
      map = map_str == "PD" ? :ρ  : 
            map_str == "dw" ? :Δw : 
            map_str == "T1" ? :T1 : 
            map_str == "T2" ? :T2 : map_str
      jwt2 = get_jwt_from_auth_header(HTTP.header(req, "Authorization"))
      uname = claims(jwt2)["username"]

      if !haskey(ACTIVE_SESSIONS, uname) # Check if the user has already an active session
         assign_process(uname) # Assign a new Julia process to the user
      end
      pid = ACTIVE_SESSIONS[uname]

      phantom_path = "phantoms/$phantom_string/$phantom_string.phantom"
      obj = read_phantom(phantom_path)
      obj.Δw .= 0
      PHANTOMS[uname] = obj

      width  = json(req)["width"]  - 15
      height = json(req)["height"] - 15
      time_samples = obj.name == "Aorta"         ? 100 : 
                     obj.name == "Flow Cylinder" ? 50  : 2;
      ss           = obj.name == "Aorta"         ? 100 : 
                     obj.name == "Flow Cylinder" ? 100 : 1;

      p = @spawnat pid plot_phantom_map(PHANTOMS[uname][1:ss:end], map; darkmode=true, width=width, height=height, time_samples=time_samples)
      html_buffer = IOBuffer()
      KomaMRIPlots.PlotlyBase.to_html(html_buffer, fetch(p).plot)
      return HTTP.Response(200,body=take!(html_buffer))
   catch e
      return HTTP.Response(500,body=JSON3.write(e))
   end
end

# --------------------- ADMIN ENDPOINTS ---------------------

@swagger """
/admin:
   get:
      tags:
      - admin
      summary: Get admin panel page
      description: Returns the administration panel HTML page for managing users, sequences, and results.
      responses:
         '200':
            description: Admin panel HTML page
            content:
              text/html:
                schema:
                  format: html
         '303':
            description: Redirect to login - not authenticated
         '403':
            description: Access denied - admin permissions required
         '500':
            description: Internal server error
"""
@get "/admin" function(req::HTTP.Request)
   println("⚠️ Received request to /admin")
   return render_html(dynamic_files_path * "/admin.html")
end

@swagger """
/api/admin/users:
   get:
      tags:
      - admin
      summary: Get all users
      description: Returns a list of all users in the system with their details and permissions.
      responses:
         '200':
            description: List of all users
            content:
              application/json:
                schema:
                  type: array
                  items:
                    type: object
                    properties:
                      id:
                        type: integer
                      username:
                        type: string
                      email:
                        type: string
                      is_premium:
                        type: boolean
                      is_admin:
                        type: boolean
                      gpu_access:
                        type: boolean
                      max_daily_sequences:
                        type: integer
                      storage_quota_mb:
                        type: number
                      created_at:
                        type: string
                        format: date-time
         '403':
            description: Access denied - admin permissions required
         '500':
            description: Internal server error
   post:
      tags:
      - admin
      summary: Create a new user
      description: Creates a new user account with the specified details and permissions.
      requestBody:
         required: true
         content:
            application/json:
               schema:
                  type: object
                  required:
                  - username
                  - password
                  - email
                  properties:
                     username:
                        type: string
                        description: Unique username for the user
                     password:
                        type: string
                        description: User password
                     email:
                        type: string
                        format: email
                        description: User email address
                     is_premium:
                        type: boolean
                        default: false
                        description: Premium user status
                     is_admin:
                        type: boolean
                        default: false
                        description: Administrator status
                     gpu_access:
                        type: boolean
                        default: false
                        description: GPU access permission
                     max_daily_sequences:
                        type: integer
                        default: 10
                        description: Maximum daily sequences allowed
                     storage_quota_mb:
                        type: number
                        default: 0.5
                        description: Storage quota in MB
      responses:
         '201':
            description: User created successfully
            content:
              application/json:
                schema:
                  type: object
                  properties:
                    id:
                      type: integer
                    username:
                      type: string
                    message:
                      type: string
         '400':
            description: Bad request - missing required fields
         '403':
            description: Access denied - admin permissions required
         '409':
            description: Conflict - username or email already exists
         '500':
            description: Internal server error
"""
@get "/api/admin/users" function(req::HTTP.Request)
   return get_all_users()
end

@post "/api/admin/users" function(req::HTTP.Request)
   # Obtener JSON y normalizar a strings
   json_data = json(req)
   println("JSON recibido en /api/admin/users: ", json_data)
   
   # Convertir a Dict y normalizar claves a strings
   input_data = normalize_keys(json_data)
   println("Campos disponibles normalizados: ", keys(input_data))
   
   # Verificar campos obligatorios con strings
   required_fields = ["username", "password", "email"]
   for field in required_fields
      if !haskey(input_data, field)
         println("❌ Required field missing: $field")
         return HTTP.Response(400, ["Content-Type" => "application/json"],
               JSON3.write(Dict("error" => "Required field missing: $field")))
      end
   end
   
   # Crear usuario con los datos validados
   try
      return admin_create_user(input_data)
   catch e
      println("❌ Error creating user: ", e)
      return HTTP.Response(500, ["Content-Type" => "application/json"],
         JSON3.write(Dict("error" => "Error al crear usuario: $e")))
   end
end

@swagger """
/api/admin/sequences:
   get:
      tags:
      - admin
      summary: Get all sequences
      description: Returns a list of all sequences created by users in the system.
      responses:
         '200':
            description: List of all sequences
            content:
              application/json:
                schema:
                  type: array
                  items:
                    type: object
                    properties:
                      id:
                        type: integer
                      username:
                        type: string
                      sequence_id:
                        type: string
                      date:
                        type: string
                        format: date
                      created_at:
                        type: string
                        format: date-time
         '403':
            description: Access denied - admin permissions required
         '500':
            description: Internal server error
"""
@get "/api/admin/sequences" function(req::HTTP.Request)
   return get_all_sequences()
end

@swagger """
/api/admin/sequences/{userId}:
   get:
      tags:
      - admin
      summary: Get sequences for a specific user
      description: Returns all sequences created by a specific user.
      parameters:
         - in: path
           name: userId
           required: true
           schema:
              type: integer
           description: The user ID
      responses:
         '200':
            description: List of sequences for the user
            content:
              application/json:
                schema:
                  type: array
                  items:
                    type: object
                    properties:
                      id:
                        type: integer
                      sequence_id:
                        type: string
                      date:
                        type: string
                        format: date
                      created_at:
                        type: string
                        format: date-time
         '403':
            description: Access denied - admin permissions required
         '404':
            description: User not found
         '500':
            description: Internal server error
"""
@get "/api/admin/sequences/{userId}" function(req::HTTP.Request, userId)
   return get_user_sequences(parse(Int, userId))
end

@swagger """
/api/admin/results/{resultId}:
   get:
      tags:
      - admin
      summary: Get result details
      description: Returns detailed information about a specific simulation result.
      parameters:
         - in: path
           name: resultId
           required: true
           schema:
              type: integer
           description: The result ID
      responses:
         '200':
            description: Result details
            content:
              application/json:
                schema:
                  type: object
                  properties:
                    id:
                      type: integer
                    username:
                      type: string
                    sequence_id:
                      type: string
                    file_path:
                      type: string
                    file_size_mb:
                      type: number
                    file_exists:
                      type: boolean
                    created_at:
                      type: string
                      format: date-time
         '403':
            description: Access denied - admin permissions required
         '404':
            description: Result not found
         '500':
            description: Internal server error
   delete:
      tags:
      - admin
      summary: Delete a simulation result
      description: Deletes a specific simulation result and its associated file.
      parameters:
         - in: path
           name: resultId
           required: true
           schema:
              type: integer
           description: The result ID to delete
      responses:
         '200':
            description: Result deleted successfully
            content:
              application/json:
                schema:
                  type: object
                  properties:
                    message:
                      type: string
         '403':
            description: Access denied - admin permissions required
         '404':
            description: Result not found
         '500':
            description: Internal server error
"""
@get "/api/admin/results/{resultId}" function(req::HTTP.Request, resultId)
   return get_result_details(parse(Int, resultId))
end

@delete "/api/admin/results/{resultId}" function(req::HTTP.Request, resultId)
   jwt1 = get_jwt_from_cookie(HTTP.header(req, "Cookie"))
   return delete_result(parse(Int, resultId), claims(jwt1)["username"])
end

@swagger """
/api/admin/stats/sequences:
   get:
      tags:
      - admin
      summary: Get sequence usage statistics
      description: Returns statistics about sequence usage including daily stats and top users.
      responses:
         '200':
            description: Sequence usage statistics
            content:
              application/json:
                schema:
                  type: object
                  properties:
                    daily_stats:
                      type: array
                      items:
                        type: object
                        properties:
                          date:
                            type: string
                            format: date
                          total_sequences:
                            type: integer
                    top_users:
                      type: array
                      items:
                        type: object
                        properties:
                          username:
                            type: string
                          total_sequences:
                            type: integer
         '403':
            description: Access denied - admin permissions required
         '500':
            description: Internal server error
"""
@get "/api/admin/stats/sequences" function(req::HTTP.Request)
   return get_sequence_usage_stats()
end

@swagger """
/api/admin/users/{userId}/sequences:
   get:
      tags:
      - admin
      summary: Get sequence usage for a specific user
      description: Returns sequence usage statistics for a specific user.
      parameters:
         - in: path
           name: userId
           required: true
           schema:
              type: integer
           description: The user ID
      responses:
         '200':
            description: User sequence usage statistics
            content:
              application/json:
                schema:
                  type: array
                  items:
                    type: object
                    properties:
                      id:
                        type: integer
                      username:
                        type: string
                      date:
                        type: string
                        format: date
                      sequences_used:
                        type: integer
         '403':
            description: Access denied - admin permissions required
         '404':
            description: User not found
         '500':
            description: Internal server error
"""
@get "/api/admin/users/{userId}/sequences" function(req::HTTP.Request, userId)
   return get_user_sequence_usage(parse(Int, userId))
end


@swagger """
/api/admin/users/{userId}:
   put:
      tags:
      - admin
      summary: Update user information
      description: Updates the information of an existing user.
      parameters:
         - in: path
           name: userId
           required: true
           schema:
              type: integer
           description: The user ID to update
      requestBody:
         required: true
         content:
            application/json:
               schema:
                  type: object
                  properties:
                     username:
                        type: string
                        description: Username (cannot be changed)
                     email:
                        type: string
                        format: email
                        description: User email address
                     is_premium:
                        type: boolean
                        description: Premium user status
                     is_admin:
                        type: boolean
                        description: Administrator status
                     gpu_access:
                        type: boolean
                        description: GPU access permission
                     max_daily_sequences:
                        type: integer
                        description: Maximum daily sequences allowed
                     storage_quota_mb:
                        type: number
                        description: Storage quota in MB
      responses:
         '200':
            description: User updated successfully
            content:
              application/json:
                schema:
                  type: object
                  properties:
                    message:
                      type: string
         '400':
            description: Bad request - invalid data
         '403':
            description: Access denied - admin permissions required
         '404':
            description: User not found
         '500':
            description: Internal server error
   delete:
      tags:
      - admin
      summary: Delete a user
      description: Deletes a user account and all associated data.
      parameters:
         - in: path
           name: userId
           required: true
           schema:
              type: integer
           description: The user ID to delete
      responses:
         '200':
            description: User deleted successfully
            content:
              application/json:
                schema:
                  type: object
                  properties:
                    message:
                      type: string
         '403':
            description: Access denied - admin permissions required
         '404':
            description: User not found
         '409':
            description: Conflict - cannot delete administrator user
         '500':
            description: Internal server error
"""
@put "/api/admin/users/{userId}" function(req::HTTP.Request, userId)
   input_data = normalize_keys(json(req))
   return update_user(parse(Int, userId), input_data)
end

@delete "/api/admin/users/{userId}" function(req::HTTP.Request, userId)
   return delete_user(parse(Int, userId))
end

@swagger """
/api/admin/users/{userId}/reset-password:
   post:
      tags:
      - admin
      summary: Reset user password
      description: Resets the password for a specific user.
      parameters:
         - in: path
           name: userId
           required: true
           schema:
              type: integer
           description: The user ID
      requestBody:
         required: true
         content:
            application/json:
               schema:
                  type: object
                  required:
                  - new_password
                  properties:
                     new_password:
                        type: string
                        description: The new password for the user
      responses:
         '200':
            description: Password reset successfully
            content:
              application/json:
                schema:
                  type: object
                  properties:
                    message:
                      type: string
         '400':
            description: Bad request - missing new password
         '403':
            description: Access denied - admin permissions required
         '404':
            description: User not found
         '500':
            description: Internal server error
"""
@post "/api/admin/users/{userId}/reset-password" function(req::HTTP.Request, userId)
   input_data = normalize_keys(json(req))
   if !haskey(input_data, "new_password")
      return HTTP.Response(400, ["Content-Type" => "application/json"],
         JSON3.write(Dict("error" => "Missing new password")))
   end
   
   return reset_user_password(parse(Int, userId), input_data["new_password"])
end

@swagger """
/api/admin/results:
   get:
      tags:
      - admin
      summary: Get all simulation results
      description: Returns a list of all simulation results in the system.
      responses:
         '200':
            description: List of all simulation results
            content:
              application/json:
                schema:
                  type: array
                  items:
                    type: object
                    properties:
                      id:
                        type: integer
                      username:
                        type: string
                      sequence_id:
                        type: string
                      file_path:
                        type: string
                      file_size_mb:
                        type: number
                      created_at:
                        type: string
                        format: date-time
         '403':
            description: Access denied - admin permissions required
         '500':
            description: Internal server error
"""
@get "/api/admin/results" function(req::HTTP.Request)
   return get_all_results()
end

@swagger """
/api/admin/sequence-usage:
   get:
      tags:
      - admin
      summary: Get all sequence usage data
      description: Returns a list of all sequence usage records in the system.
      responses:
         '200':
            description: List of all sequence usage records
            content:
              application/json:
                schema:
                  type: array
                  items:
                    type: object
                    properties:
                      id:
                        type: integer
                      username:
                        type: string
                      date:
                        type: string
                        format: date
                      sequences_used:
                        type: integer
         '403':
            description: Access denied - admin permissions required
         '500':
            description: Internal server error
"""
@get "/api/admin/sequence-usage" function(req::HTTP.Request)
   return get_all_sequence_usage()
end

@swagger """
/api/admin/sequence-usage/{usageId}:
   get:
      tags:
      - admin
      summary: Get sequence usage by ID
      description: Returns a specific sequence usage record by its ID.
      parameters:
         - in: path
           name: usageId
           required: true
           schema:
              type: integer
           description: The sequence usage ID
      responses:
         '200':
            description: Sequence usage record
            content:
              application/json:
                schema:
                  type: object
                  properties:
                    id:
                      type: integer
                    username:
                      type: string
                    date:
                      type: string
                      format: date
                    sequences_used:
                      type: integer
         '403':
            description: Access denied - admin permissions required
         '404':
            description: Sequence usage record not found
         '500':
            description: Internal server error
   put:
      tags:
      - admin
      summary: Update sequence usage record
      description: Updates the sequence usage count for a specific record.
      parameters:
         - in: path
           name: usageId
           required: true
           schema:
              type: integer
           description: The sequence usage ID to update
      requestBody:
         required: true
         content:
            application/json:
               schema:
                  type: object
                  required:
                  - sequences_used
                  properties:
                     sequences_used:
                        type: integer
                        description: The number of sequences used
      responses:
         '200':
            description: Sequence usage updated successfully
            content:
              application/json:
                schema:
                  type: object
                  properties:
                    message:
                      type: string
         '400':
            description: Bad request - missing sequences_used field
         '403':
            description: Access denied - admin permissions required
         '404':
            description: Sequence usage record not found
         '500':
            description: Internal server error
"""
@get "/api/admin/sequence-usage/{usageId}" function(req::HTTP.Request, usageId)
   return get_sequence_usage_by_id(parse(Int, usageId))
end

@put "/api/admin/sequence-usage/{usageId}" function(req::HTTP.Request, usageId)
   input_data = normalize_keys(json(req))
   if !haskey(input_data, "sequences_used")
      return HTTP.Response(400, ["Content-Type" => "application/json"],
         JSON3.write(Dict("error" => "Missing sequences_used field")))
   end
   return update_sequence_usage(parse(Int, usageId), input_data["sequences_used"])
end

# Redirect /results to /results.html 
@get "/results" function(req::HTTP.Request)
   return render_html(dynamic_files_path * "/results.html")
end

@swagger """
/api/results:
   get:
      tags:
      - results
      summary: Get user's simulation results
      description: Returns all simulation results for the authenticated user.
      responses:
         '200':
            description: List of user's simulation results
            content:
              application/json:
                schema:
                  type: array
                  items:
                    type: object
                    properties:
                      id:
                        type: integer
                      sequence_id:
                        type: string
                      file_path:
                        type: string
                      file_size_mb:
                        type: number
                      created_at:
                        type: string
                        format: date-time
         '401':
            description: Not authenticated
         '500':
            description: Internal server error
"""
# Endpoint for the results API
@get "/api/results" function(req)
   username = get_user_from_jwt(req)
   results = get_user_results(username)
   return HTTP.Response(200, ["Content-Type" => "application/json"], JSON3.write(results))
end

@swagger """
/api/results/{id}/download:
   get:
      tags:
      - results
      summary: Download simulation result
      description: Downloads a specific simulation result file for the authenticated user.
      parameters:
         - in: path
           name: id
           required: true
           schema:
              type: integer
           description: The result ID to download
      responses:
         '200':
            description: File download
            content:
              application/octet-stream:
                schema:
                  type: string
                  format: binary
         '401':
            description: Not authenticated
         '403':
            description: Access denied - result belongs to another user
         '404':
            description: Result not found
         '500':
            description: Internal server error
"""
@get "/api/results/{id}/download" function(req, id)
   println("searching for user id")
   username = get_user_from_jwt(req)
      println("Download requested: user=$username, id=$id")
   return download_simulation_result(username, parse(Int, id))
end

@swagger """
/api/results/{id}:
   delete:
      tags:
      - results
      summary: Delete simulation result
      description: Deletes a specific simulation result for the authenticated user.
      parameters:
         - in: path
           name: id
           required: true
           schema:
              type: integer
           description: The result ID to delete
      responses:
         '200':
            description: Result deleted successfully
            content:
              application/json:
                schema:
                  type: object
                  properties:
                    message:
                      type: string
         '401':
            description: Not authenticated
         '403':
            description: Access denied - result belongs to another user
         '404':
            description: Result not found
         '500':
            description: Internal server error
"""
@delete "/api/results/{id}" function(req, id)
   return delete_result(parse(Int, id), claims(jwt1)["username"])
end
# ---------------------------------------------------------------------------

# title and version are required
info = Dict("title" => "MRSeqStudio API", "version" => "1.0.0")
openApi = OpenAPI("3.0", info)
swagger_document = build(openApi)
  
# merge the SwaggerMarkdown schema with the internal schema
setschema(swagger_document)

serve(host="0.0.0.0",port=8000, middleware=[AuthMiddleware])