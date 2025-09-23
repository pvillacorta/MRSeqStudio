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
using SwaggerMarkdown
using SHA
using JWTs, MbedTLS

using StatsBase, FFTW
using StructTypes

@everywhere begin
   using KomaMRI
   using LinearAlgebra
   using JSON3
   using Dates
   # using CUDA #TODO: Find a way to choose between CPU and GPU
end

dynamic_files_path = string(@__DIR__, "/../frontend/dist")
phantom_files_path = string(@__DIR__, "/phantoms")

dynamicfiles(dynamic_files_path, "/") 
staticfiles(phantom_files_path, "/public")

const PUBLIC_URLS = ["/login", "/login.js", "/login.js.map", "/register"]
const PRIVATE_URLS = ["/simulate", "/recon", "/plot_sequence", "/plot_phantom"]

const AUTH_FILE  = "auth.txt"
const USERS_FILE = "users.txt"

global simID = 1
# Dictionaries whose key is the simulation ID
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
# User-Process correspondence (Key:username, Value:pid)
global ACTIVE_SESSIONS  = Dict{String, Int}()

# ------------------------------ FUNCTIONS ------------------------------------
@everywhere begin
   include("api_utils.jl")
   include("mri_utils.jl")
   include("users.jl")

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

## AUTHENTICATION
function AuthMiddleware(handler)
   return function(req::HTTP.Request)
      println("Auth middleware")

      path = String(req.target)

      jwt1 = get_jwt_from_cookie(HTTP.header(req, "Cookie"))
      jwt2 = get_jwt_from_auth_header(HTTP.header(req, "Authorization"))

      ipaddr = string(HTTP.header(req, "X-Forwarded-For", "127.0.0.1"))

      if (path in PUBLIC_URLS) 
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
   input_data = json(req)
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
   input_data = json(req)
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
   scanner_json   = json(req)["scanner"]
   sequence_json  = json(req)["sequence"]

   jwt2 = get_jwt_from_auth_header(HTTP.header(req, "Authorization"))
   uname = claims(jwt2)["username"]

   if !haskey(ACTIVE_SESSIONS, uname) # Check if the user has already an active session
      assign_process(uname) # We assign a new julia process to the user
   end

   pid = ACTIVE_SESSIONS[uname]

   STATUS_FILES[simID] = tempname()
   touch(STATUS_FILES[simID])
   
   SCANNERS[uname]                       = json_to_scanner(scanner_json)
   SEQUENCES[uname], ROT_MATRICES[uname] = json_to_sequence(sequence_json, SCANNERS[uname])

   RAW_RESULTS[uname]                    = @spawnat pid sim(PHANTOMS[uname], SEQUENCES[uname], SCANNERS[uname], STATUS_FILES[simID])
   
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
# ---------------------------------------------------------------------------

# title and version are required
info = Dict("title" => "MRSeqStudio API", "version" => "1.0.0")
openApi = OpenAPI("3.0", info)
swagger_document = build(openApi)
  
# merge the SwaggerMarkdown schema with the internal schema
setschema(swagger_document)

serve(host="0.0.0.0",port=8000, middleware=[AuthMiddleware])
