class MysqlRewinder
  module MethodLogging
    def self.calculate_target_classes
      target_classes = []
      current_modules = [MysqlRewinder]
      loop do
        break if current_modules.empty?

        while current_module = current_modules.pop
          target_classes << current_module if current_module.is_a?(Class)
          current_module.constants.each do |child_constant_name|
            child_constant = current_module.const_get(child_constant_name)
            if child_constant.is_a?(Module)
              current_modules << child_constant
            end
          end
        end
      end
      target_classes - [self.class]
    end

    def self.convert_args_to_string(args, kwargs, block)
      args_string = args.empty? ? nil : args.map(&:inspect).join(', ')
      kwargs_string = kwargs.empty? ? nil : kwargs
      block = block ? "block ==> #{block}" : nil

      [args_string, kwargs_string, block].compact.join(', ')
    end

    def self.prepend_logger_to_singleton_methods(target_class, logger)
      mod = Module.new do
        target_class.singleton_methods(false).each do |singleton_method_name|
          define_method singleton_method_name do |*args, **kwargs, &block|
            MethodLogging.incur_padding
            logger.debug { "#{MethodLogging.padding}[MysqlRewinder] #{target_class}.#{singleton_method_name}(#{MethodLogging.convert_args_to_string(args, kwargs, block)})" }
            super(*args, **kwargs, &block)
          ensure
            MethodLogging.decur_padding
          end
        end
      end
      target_class.singleton_class.prepend mod
    end

    def self.prepend_logger_to_instance_methods(target_class, logger)
      mod = Module.new do
        target_class.instance_methods(false).each do |method_name|
          define_method method_name do |*args, **kwargs, &block|
            MethodLogging.incur_padding
            logger.debug { "#{MethodLogging.padding}[MysqlRewinder] #{target_class}\##{method_name}(#{MethodLogging.convert_args_to_string(args, kwargs, block)})" }
            logger.debug { "#{MethodLogging.padding}[MysqlRewinder] ========= instance inspection starts =======" }
            logger.debug { "#{MethodLogging.padding}  [MysqlRewinder] #{self.inspect}" }
            logger.debug { "#{MethodLogging.padding}[MysqlRewinder] ========= instance inspection finishes =======" }
            super(*args, **kwargs, &block)
          ensure
            MethodLogging.decur_padding
          end
        end
      end
      target_class.prepend mod
    end

    def self.incur_padding
      @padding ||= 0
      @padding += 1
    end

    def self.decur_padding
      @padding ||= 0
      @padding -= 1
    end

    def self.padding
      @padding ||= 0
      ' ' * @padding * 2
    end
  end
end