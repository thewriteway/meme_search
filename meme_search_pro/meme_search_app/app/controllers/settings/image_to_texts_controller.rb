module Settings
  class ImageToTextsController < ApplicationController
    # GET /image_to_texts or /image_to_texts.json
    def index
      # return ordered by id
      @image_to_texts = ImageToText.order(id: :asc)
    end

    def update_current
      # Unset all "current" values
      ImageToText.update_all(current: false)

      # puts all params
      puts params

      # Set the selected "current" record
      if params[:current_id].present?
        ImageToText.find(params[:current_id]).update(current: true)
      end

      # Get name of the current model
      current_model = ImageToText.find_by(current: true).name

      # puts all image_to_texts
      puts ImageToText.all

      respond_to do |format|
        flash = { notice: "Current model set to: #{current_model}" }
        format.html { redirect_to [ :settings, :image_to_texts ], flash: flash }
      end
    end

    private
      # Use callbacks to share common setup or constraints between actions.
      def set_image_to_text
        @image_to_text = ImageToText.find(params[:id])
      end

      # Only allow a list of trusted parameters through.
      def image_to_text_params
        params.require(:image_to_text).permit(:name, :description)
      end
  end
end
