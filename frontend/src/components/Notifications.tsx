import { useSubscription, gql } from '@apollo/client';
import { useEffect } from 'react';
import toast from 'react-hot-toast';

const ORDER_UPDATED_SUBSCRIPTION = gql`
  subscription OnOrderUpdated {
    onOrderUpdated {
      id
      status
    }
  }
`;

const GATEWAY_RELOADED_SUBSCRIPTION = gql`
  subscription OnGatewayReloaded {
    onGatewayReloaded
  }
`;

export default function Notifications() {
  const { data: orderData } = useSubscription(ORDER_UPDATED_SUBSCRIPTION);
  const { data: gatewayData } = useSubscription(GATEWAY_RELOADED_SUBSCRIPTION);

  useEffect(() => {
    if (orderData?.onOrderUpdated) {
      const { id, status } = orderData.onOrderUpdated;
      if (status === 'Processed') {
        toast.success(`Order ${id} has been PROCESSED by the Back Office!`, {
          duration: 5000,
          icon: '🚀',
          style: {
            borderRadius: '10px',
            background: '#333',
            color: '#fff',
          },
        });
      }
    }
  }, [orderData]);

  useEffect(() => {
    if (gatewayData?.onGatewayReloaded) {
      toast(gatewayData.onGatewayReloaded, {
        duration: 5000,
        icon: '🔄',
        style: {
          borderRadius: '10px',
          background: '#2196F3',
          color: '#fff',
        },
      });
    }
  }, [gatewayData]);

  return null; // This component doesn't render anything visible
}
