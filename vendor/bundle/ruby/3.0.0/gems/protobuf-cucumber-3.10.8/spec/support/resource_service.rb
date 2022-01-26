require PROTOS_PATH.join('resource.pb')

Test::ResourceService.class_eval do
  # request -> Test::ResourceFindRequest
  # response -> Test::Resource
  def find
    response.name = request.name
    response.status = request.active ? 1 : 0
  end

  # request -> Test::ResourceSleepRequest
  # response -> Test::Resource
  def find_with_sleep
    sleep(request.sleep || 1)
    response.name = 'Request should have timed out'
  end

  # request -> Test::ResourceFindRequest
  # response -> Test::Resource
  def find_with_rpc_failed
    rpc_failed('Find failed')
  end
end
