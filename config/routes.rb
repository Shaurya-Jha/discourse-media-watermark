# frozen_string_literal: true

DiscourseMediaWatermark::Engine.routes.draw do
  get "/examples" => "examples#index"
  # define routes here
end

Discourse::Application.routes.draw { mount ::DiscourseMediaWatermark::Engine, at: "discourse-media-watermark" }
