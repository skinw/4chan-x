CrossOrigin = do ->
  <% if (type === 'crx') { %>
  eventPageRequest = do ->
    callbacks = []
    chrome.runtime.onMessage.addListener (data) ->
      callbacks[data.id] data
      delete callbacks[data.id]
    (url, responseType, cb) ->
      chrome.runtime.sendMessage {url, responseType}, (id) ->
        callbacks[id] = cb
  <% } %>

  binary: (url, cb, headers={}) ->
    <% if (type === 'crx') { %>
    if /^https:\/\//.test(url) or location.protocol is 'http:'
      xhr = new XMLHttpRequest()
      xhr.open 'GET', url, true
      xhr.setRequestHeader key, value for key, value of headers
      xhr.responseType = 'arraybuffer'
      xhr.onload = ->
        return cb null unless @readyState is @DONE and @status in [200, 206]
        contentType        = @getResponseHeader 'Content-Type'
        contentDisposition = @getResponseHeader 'Content-Disposition'
        cb new Uint8Array(@response), contentType, contentDisposition
      xhr.onerror = xhr.onabort = ->
        cb null
      xhr.send()
    else
      eventPageRequest url, 'arraybuffer', ({response, contentType, contentDisposition, error}) ->
        return cb null if error
        cb new Uint8Array(response), contentType, contentDisposition
    <% } %>
    <% if (type === 'userscript') { %>
    GM_xmlhttpRequest
      method: "GET"
      url: url
      headers: headers
      overrideMimeType: "text/plain; charset=x-user-defined"
      onload: (xhr) ->
        r = xhr.responseText
        data = new Uint8Array r.length
        i = 0
        while i < r.length
          data[i] = r.charCodeAt i
          i++
        contentType        = xhr.responseHeaders.match(/Content-Type:\s*(.*)/i)?[1]
        contentDisposition = xhr.responseHeaders.match(/Content-Disposition:\s*(.*)/i)?[1]
        cb data, contentType, contentDisposition
      onerror: ->
        cb null
      onabort: ->
        cb null
    <% } %>

  file: (url, cb) ->
    CrossOrigin.binary url, (data, contentType, contentDisposition) ->
      return cb null unless data?
      name = url.match(/([^\/]+)\/*$/)?[1]
      mime = contentType?.match(/[^;]*/)[0] or 'application/octet-stream'
      match =
        contentDisposition?.match(/\bfilename\s*=\s*"((\\"|[^"])+)"/i)?[1] or
        contentType?.match(/\bname\s*=\s*"((\\"|[^"])+)"/i)?[1]
      if match
        name = match.replace /\\"/g, '"'
      blob = new Blob([data], {type: mime})
      blob.name = name
      cb blob

  json: do ->
    callbacks = {}
    responses = {}
    (url, cb) ->
      <% if (type === 'crx') { %>
      if /^https:\/\//.test(url) or location.protocol is 'http:'
        return $.cache url, (-> cb @response), responseType: 'json'
      <% } %>
      if responses[url]
        cb responses[url]
        return
      if callbacks[url]
        callbacks[url].push cb
        return
      callbacks[url] = [cb]
      <% if (type === 'userscript') { %>
      GM_xmlhttpRequest
        method: "GET"
        url: url+''
        onload: (xhr) ->
          response = JSON.parse xhr.responseText
          cb response for cb in callbacks[url]
          delete callbacks[url]
          responses[url] = response
        onerror: ->
          delete callbacks[url]
        onabort: ->
          delete callbacks[url]
      <% } %>
      <% if (type === 'crx') { %>
      eventPageRequest url, 'json', ({response, error}) ->
        if error
          delete callbacks[url]
        else
          cb response for cb in callbacks[url]
          delete callbacks[url]
          responses[url] = response
      <% } %>
