defmodule MiakTech.Windmill do
  @base      "https://app.windmill.dev/api"
  @workspace "dev-tst"

  def run(script_path, args) do
    token = Application.fetch_env!(:miak_tech, :windmill_token)

    response = Req.post!(
      "#{@base}/w/#{@workspace}/jobs/run_wait_result/p/#{script_path}",
      json: args,
      headers: [{"Authorization", "Bearer #{token}"}],
      receive_timeout: 120_000
    )

    response.body
  end
end
