## Node

Base class for all the node wrappers. 

The Mooog Node object wraps one or more AudioNode objects. By default it 
exposes the `AudioNode` methods of the first AudioNode in the `_nodes`
array. 

Signatures:

> Node(instance:Mooog , id:string, node_def:mixed)

`_instance`: The parent `Mooog` instance  
`id`: A unique identifier to assign to this Node
`node_def`: Either a string representing the type of Node to initialize
or an object with initialization params (see below) 



> Node(instance:Mooog , node_definition:object [, node_definition...])

`_instance`: The parent `Mooog` instance  
`node_definition`: An object used to create and configure the new Node. 

Required properties:
  - `id`: Unique string identifier
  - `node_type`: String indicating the type of Node (Oscillator, Gain, etc.)
  
Optional properties
  - `connect_to_destination`: Boolean indicating whether the last in this node's 
`_nodes` array is automatically connected to the `AudioDestinationNode`. *default: true*

Additional properties  
  - Any additional key-value pairs will be used to set properties of the underlying `AudioNode`
object after initialization. 



    class Node
      constructor: (@_instance, node_list...) ->
        @_destination = @_instance._destination
        @context = @_instance.context
        @_nodes = []
        @config_defaults =
          connect_to_destination: true
        @config = {}
        
Take care of first type signature (ID and string type)

        if @__typeof(node_list[0]) is "string" \
        and @__typeof(node_list[1]) is "string" \
        and Mooog.LEGAL_NODES[node_list[1]]?
          return new Mooog.LEGAL_NODES[node_list[1]] @_instance, { id: node_list[0] }

Otherwise, this is one or more config objects.
        
        if node_list.length is 1
          return unless @constructor.name is "Node"
          if Mooog.LEGAL_NODES[node_list[0].node_type]?
            return new Mooog.LEGAL_NODES[node_list[0].node_type] @_instance, node_list[0]
          else
            throw new Error("Omitted or undefined node type in config options.")
        else
          for i in node_list
            if Mooog.LEGAL_NODES[node_list[i].node_type?]
              @_nodes.push new Mooog.LEGAL_NODES[node_list[i].node_type] @_instance, node_list[i]
            else
              throw new Error("Omitted or undefined node type in config options.")

        

### Node.configure_from
The config object can contain general configuration options or key/value pairs to be set on the
wrapped `AudioNode`. This function merges the config defaults with the supplied options and sets
the `config` property of the node
      
      configure_from: (ob) ->
        @id = if ob.id? then ob.id else @new_id()
        for k, v of @config_defaults
          @config[k] = if (k of ob) then ob[k] else @config_defaults[k]
        @config


### Node.zero_node_settings
XORs the supplied configuration object with the defaults to return an object the properties of which
should be set on the zero node
      
      zero_node_settings: (ob) ->
        zo = {}
        for k, v of ob
          zo[k] = v unless k of @config_defaults or k is 'node_type' or k is 'id'
        zo
        

### Node.zero_node_setup
Runs after the Node constructor by the inheriting classes. Exposes the underlying `AudioNode` 
properties and sets any `AudioNode`-specific properties supplied in the configuration object.
      
      zero_node_setup: (config) ->
        @expose_methods_of @_nodes[0]
        for k, v of @zero_node_settings(config)
          @param k, v
        
### Node.toString
Includes the ID in the string representation of the object.      

      toString: () ->
        "#{@.constructor.name}#"+@id



### Node.new_id
Generates a new string identifier for this node.
      
      
      new_id: () ->
        "#{@.constructor.name}_#{Math.round(Math.random()*100000)}"


### Node.__typeof
This is a modified `typeof` to filter AudioContext API-specific object types
      
      
      __typeof: (thing) ->
        return "AudioParam" if thing instanceof AudioParam
        return "AudioNode" if thing instanceof AudioNode
        return "AudioBuffer" if thing instanceof AudioBuffer
        return "Node" if thing instanceof Node
        switch typeof(thing)
          when "string" then "string"
          when "number" then "number"
          when "function" then "function"
          when "object" then "object"
          when "boolean" then "boolean"
          when "undefined" then "undefined"
          else
            throw new Error "__typeof does not pass for " + typeof(thing)
            
      
### Node.insert_node


      insert_node: (node, ord) ->
        length = @_nodes.length
        ord = length unless ord?
                
        if ord > length
          throw new Error("Invalid index given to insert_node: " + ord +
          " out of " + length)
        @debug "insert_node of #{@} for", node, ord

        if ord is 0
          @connect_incoming node
          @disconnect_incoming @_nodes[0]

          if length > 1
            node.connect @to @_nodes[0]
            @debug '- node.connect to ', @_nodes[0]

        if ord is length
          @safely_disconnect @_nodes[ord - 1], (@from @_destination) if ord isnt 0
          @debug("- disconnect ", @_nodes[ord - 1], 'from', @_destination) if ord isnt 0
          
          if @config.connect_to_destination
            node.connect @to @_destination
            @debug '- connect', node, 'to', @_destination
          
          @_nodes[ord - 1].connect @to node if ord isnt 0
          @debug '- connect', @_nodes[ord - 1], "to", node if ord isnt 0

        if ord isnt length and ord isnt 0
          @safely_disconnect @_nodes[ord - 1], (@from @_nodes[ord])
          @debug "- disconnect", @_nodes[ord - 1], "from", @_nodes[ord]
          @_nodes[ord - 1].connect @to node
          @debug "- connect", @_nodes[ord - 1], "to", node
          node.connect @to @_nodes[ord]
          @debug "- connect", node, "to", @_nodes[ord]
        
        @_nodes.splice ord, 0, node
        @debug "- spliced:", @_nodes

  
### Node.add
Shortcut for insert_node


      add: (node) ->
        @insert_node(node)
          

      connect_incoming: ->
        #@debug 'do incoming'
        #todo: deal with incoming connections for 0 element

      disconnect_incoming: ->
        #@debug 'undo incoming'
        #todo: deal with incoming connections for 0 element


### Node.connect
`node`: The node object or string ID of the object to which to connect.  
`param`: Optional string name of the `AudioParam` member of `node` to
which to connect.  
`output`: Optional integer representing the output of this Node to use.  
`input`: If `param` is not specified (you are connecting to an `AudioNode`)
then this integer argument can be used to specify the input of the target
to connect to.  



      connect: (node, output = 0, input = 0, return_this = true) ->
        @debug "called connect from #{@} to #{node}, #{output}"
        
        switch @__typeof node
          
          when "AudioParam"
            @_nodes[ @_nodes.length - 1 ].connect node, output
            return this
          when "string"
            node = @_instance.node node
            target = node._nodes[0]
          when "Node"
            target = node._nodes[0]
          when "AudioNode"
            target = node
          else throw new Error "Unknown node type passed to connect"
          
        switch
          when typeof(output) is 'string'
            @_nodes[ @_nodes.length - 1 ].connect target[output], input
          when typeof(output) is 'number'
            @_nodes[ @_nodes.length - 1 ].connect target, output, input
        
        return if return_this then this else node



### Node.chain
Like `Node.connect` but returns the `Node` you are connecting to. To use
with `AudioParam`s, use the name of the param as the second argument (and
the base `Node` as the first).

      chain: (node, output = 0, input = 0) ->
        
        @debug node, @__typeof(node), typeof(output)
        if @__typeof(node) is "AudioParam" and typeof(output) isnt 'string'
          throw new Error "Node.chain() can only target AudioParams when used with
          the signature .chain(target_node:Node, target_param_name:string)"
        @connect node, output, input, false


### Node.to, Node.from
These functions are synonyms and exist to improve code readability.
      
      to: (node) ->
        switch @__typeof node
          when "Node" then return node._nodes[0]
          when "AudioNode" then return node
          else throw new Error "Unknown node type passed to connect"
      
      from: @.prototype.to
      

### Node.expose_methods_of
Exposes the properties of a wrapped `AudioNode` on `this`

      
      expose_methods_of: (node) ->
        @debug "exposing", node
        for key,val of node
          if @[key]? then continue
          #@debug "- checking #{key}: got", @__typeof val
          switch @__typeof val
            when 'function'
              @[key] = val.bind node
            when 'AudioParam'
              @[key] = val
            when "string", "number", "boolean", "object"
              ((o, node, key) ->
                Object.defineProperty o, key, {
                  get: ->
                    node[key]
                  set: (val) ->
                    node[key] = val
                  enumerable: true
                  configurable: true
                })(@, node, key)



### Node.safely_disconnect
Prevents `InvalidAccessError`s from stopping program execution if you try to use disconnect on 
a node that's not already connected.

      safely_disconnect: (node1, node2, output = 0, input = 0) ->
        switch @__typeof node1
          when "Node" then source = node1._nodes[ node1._nodes.length - 1 ]
          when "AudioNode", "AudioParam" then source = node1
          else throw new Error "Unknown node type passed to connect"
        switch @__typeof node2
          when "Node" then target = node2._nodes[0]
          when "AudioNode", "AudioParam" then target = node2
          else throw new Error "Unknown node type passed to connect"
        try
          source.disconnect target, output, input
        catch e
          @debug("ignored InvalidAccessError disconnecting #{target} from #{source}")
        @

      
### Node.disconnect
Replace the native `disconnect` function with a safe version, in case it is called directly.

      disconnect: (node, output = 0, input = 0) ->
        @safely_disconnect @, node, output, input



### Node.param
jQuery-style getter/setter that also works on `AudioParam` properties.
  
      param: (key, val) ->
        if @__typeof(key) is 'object'
          @get_set k, v for k, v of key
          return this
        @get_set key, val
        return this



### Node.get_set
Handles the getting/setting for `Node.param`

      get_set: (key, val) ->
        return unless @[key]?
        switch @__typeof @[key]
          when "AudioParam"
            if val?
              @[key].value = val
              return this
            else @[key].value
          else
            if val?
              @[key] = val
              return this
            else @[key]


### Node.define_buffer_source_properties
Sets up useful functions on `Node`s that have a `buffer` property 
      
      define_buffer_source_properties: () ->
        @_buffer_source_file_url = ''
        Object.defineProperty @, 'buffer_source_file', {
          get: ->
            @_buffer_source_file_url
          set: (filename) =>
            request = new XMLHttpRequest()
            request.open('GET', filename, true)
            request.responseType = 'arraybuffer'
            request.onload = () =>
              @debug "loaded #{filename}"
              @_buffer_source_file_url = filename
              @_instance.context.decodeAudioData request.response, (buffer) =>
                @debug "setting buffer",buffer
                @buffer = buffer
              , (error) ->
                throw new Error("Could not decode audio data from #{request.responseURL}
                 - unsupported file format?")
            request.send()
          enumerable: true
          configurable: true
        }

      



### Node.debug
Logs to the console if the debug config option is on
  
      debug: (a...) ->
        console.log(a...) if @_instance.config.debug
