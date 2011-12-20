module Fog
  module Storage
    class AWS
      class Real

        # Delete an object from S3
        #
        # ==== Parameters
        # * bucket_name<~String> - Name of bucket containing object to delete
        # * object_name<~String> - Name of object to delete
        #
        # ==== Returns
        # * response<~Excon::Response>:
        #   * status<~Integer> - 204
        #
        # ==== See Also
        # http://docs.amazonwebservices.com/AmazonS3/latest/API/RESTObjectDELETE.html

        def delete_object(bucket_name, object_name, options = {})
          if version_id = options.delete('versionId')
            path = "#{CGI.escape(object_name)}?versionId=#{CGI.escape(version_id)}"
          else
            path = CGI.escape(object_name)
          end

          headers = options
          request({
            :expects    => 204,
            :headers    => headers,
            :host       => "#{bucket_name}.#{@host}",
            :idempotent => true,
            :method     => 'DELETE',
            :path       => path
          })
        end

      end

      class Mock # :nodoc:all

        def delete_object(bucket_name, object_name, options = {})
          response = Excon::Response.new
          if bucket = self.data[:buckets][bucket_name]
            response.status = 204

            version_id = options.delete('versionId')

            if bucket[:versioning]
              bucket[:objects][object_name] ||= []

              if version_id
                version = bucket[:objects][object_name].find { |object| object['VersionId'] == version_id}

                # S3 special cases the 'null' value to not error out if no such version exists.
                if version || version_id == 'null'
                  bucket[:objects][object_name].delete(version)

                  response.headers['x-amz-delete-marker'] = 'true' if version[:delete_marker]
                  response.headers['x-amz-version-id'] = version_id
                else
                  response.status = 400
                  response.body = invalid_version_id_payload(version_id)
                end
              else
                delete_marker = {
                  :delete_marker    => true,
                  'Key'             => object_name,
                  'VersionId'       => Fog::Mock.random_base64(32),
                  'Last-Modified'   => Fog::Time.now.to_date_header
                }

                bucket[:objects][object_name] << delete_marker
                response.headers['x-amz-delete-marker'] = 'true'
                response.headers['x-amz-version-id'] = delete_marker['VersionId']
              end
            else
              if version_id && version_id != 'null'
                response.status = 400
                response.body = invalid_version_id_payload(version_id)
              else
                bucket[:objects].delete(object_name)

                response.headers['x-amz-version-id'] = 'null'
              end
            end
          else
            response.status = 404
            raise(Excon::Errors.status_error({:expects => 204}, response))
          end
          response
        end

        private

        def invalid_version_id_payload(version_id)
          {
            'Error' => {
              'Code' => 'InvalidArgument',
              'Message' => 'Invalid version id specified',
              'ArgumentValue' => version_id,
              'ArgumentName' => 'versionId',
              'RequestId' => Fog::Mock.random_hex(16),
              'HostId' => Fog::Mock.random_base64(65)
            }
          }
        end

      end
    end
  end
end
