# Copyright 2018 OmiseGO Pte Ltd
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

defmodule OMG.Watcher.Web.View.Challenge do
  @moduledoc """
  The challenge view for rendering json
  """

  use OMG.Watcher.Web, :view
  alias Utils.JsonRPC.Response

  def render("challenge.json", %{response: challenge}) do
    challenge
    |> Response.serialize()
  end
end
