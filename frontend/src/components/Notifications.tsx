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

export default function Notifications() {
  const { data, loading } = useSubscription(ORDER_UPDATED_SUBSCRIPTION);

  useEffect(() => {
    if (data?.onOrderUpdated) {
      const { id, status } = data.onOrderUpdated;
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
  }, [data]);

  return null; // This component doesn't render anything visible
}
